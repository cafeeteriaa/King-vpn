#![deny(unsafe_op_in_unsafe_fn)]

use std::ffi::CStr;

const MAX_FFI_BATCH: u32 = 8192;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::str::FromStr;

fn address_value(ip: IpAddr) -> (u128, u8) {
    match ip {
        IpAddr::V4(v) => (u32::from(v) as u128, 32),
        IpAddr::V6(v) => (u128::from(v), 128),
    }
    #[test]
    fn ffi_rejects_oversized_batches_before_allocating() {
        let input = CString::new("192.0.2.0/24").unwrap();
        let cursor = CString::new("0").unwrap();
        let mut output = [0u8; 128];
        let result = unsafe {
            king_expand_range_batch(
                input.as_ptr(),
                cursor.as_ptr(),
                8193,
                output.as_mut_ptr(),
                output.len(),
            )
        };
        assert_eq!(result, -1);
    }

}

fn format_address(value: u128, width: u8) -> String {
    if width == 32 {
        Ipv4Addr::from(value as u32).to_string()
    } else {
        Ipv6Addr::from(value).to_string()
    }
}

fn parse_span(input: &str) -> Option<(u128, u128, u8)> {
    let value = input.trim();
    if value.is_empty() {
        return None;
    }
    if let Some((address, prefix_text)) = value.split_once('/') {
        let ip = IpAddr::from_str(address.trim()).ok()?;
        let prefix = prefix_text.trim().parse::<u8>().ok()?;
        let (raw, width) = address_value(ip);
        if prefix > width {
            return None;
        }
        let host_bits = width - prefix;
        let mask = if host_bits == 128 {
            u128::MAX
        } else if host_bits == 0 {
            0
        } else {
            (1u128 << host_bits) - 1
        };
        let low = raw & !mask;
        return Some((low, low | mask, width));
    }
    if let Some((first, last)) = value.split_once('-') {
        let (a, width) = address_value(IpAddr::from_str(first.trim()).ok()?);
        let (b, last_width) = address_value(IpAddr::from_str(last.trim()).ok()?);
        if width != last_width {
            return None;
        }
        return Some((a.min(b), a.max(b), width));
    }
    let (address, width) = address_value(IpAddr::from_str(value).ok()?);
    Some((address, address, width))
}

fn expand_range_batch(
    input: &str,
    cursor_text: &str,
    limit: usize,
) -> Option<(Vec<String>, String)> {
    let (low, high, width) = parse_span(input)?;
    let cursor = cursor_text.trim().parse::<u128>().unwrap_or(0);
    let full_u128_span = low == 0 && high == u128::MAX;
    let (offset, count, next, wraps) = if full_u128_span {
        // 2^128 cannot be represented by u128; handle the full IPv6 /0 explicitly.
        let available = if cursor == 0 {
            u128::MAX
        } else {
            u128::MAX - cursor + 1
        };
        let count = limit.min(available.min(usize::MAX as u128) as usize);
        (cursor, count, match cursor.checked_add(count as u128) { Some(value) => value, None => 0 }, false)
    } else {
        let span = high.checked_sub(low)?.checked_add(1)?;
        let offset = cursor % span;
        if width == 32 {
            // Match existing IPv4 behavior: a page may wrap at the range end.
            let count = limit.min(span.min(usize::MAX as u128) as usize);
            (offset, count, (offset + count as u128) % span, true)
        } else {
            let remaining = span - offset;
            let count = limit.min(remaining.min(usize::MAX as u128) as usize);
            (offset, count, (offset + count as u128) % span, false)
        }
    };
    let span = if full_u128_span { None } else { Some(high - low + 1) };
    let mut addresses = Vec::with_capacity(count);
    for index in 0..count {
        let relative = if wraps {
            (offset + index as u128) % span?
        } else {
            offset.checked_add(index as u128)?
        };
        addresses.push(format_address(low.checked_add(relative)?, width));
    }
    Some((addresses, next.to_string()))
}

/// Returns bytes written; -1 invalid pointer/input; -2 output buffer too small.
/// Output is UTF-8: decimal next cursor, newline, then one IP per line.
///
/// # Safety
/// Pointers must remain valid during the call. Input and cursor must be
/// NUL-terminated UTF-8 strings; output must be writable for output_capacity bytes.
#[no_mangle]
pub unsafe extern "C" fn king_expand_range_batch(
    input: *const c_char,
    cursor: *const c_char,
    limit: u32,
    output: *mut u8,
    output_capacity: usize,
) -> isize {
    if input.is_null() || cursor.is_null() || output.is_null() || limit > MAX_FFI_BATCH {
        return -1;
    }
    let result = catch_unwind(AssertUnwindSafe(|| {
        let input = unsafe { CStr::from_ptr(input) }.to_str().ok()?;
        let cursor = unsafe { CStr::from_ptr(cursor) }.to_str().ok()?;
        let (addresses, next) = expand_range_batch(input, cursor, limit as usize)?;
        let mut encoded = String::with_capacity(40 + addresses.len() * 42);
        encoded.push_str(&next);
        encoded.push('\n');
        for address in addresses {
            encoded.push_str(&address);
            encoded.push('\n');
        }
        if encoded.len() > output_capacity {
            return None;
        }
        unsafe { std::ptr::copy_nonoverlapping(encoded.as_ptr(), output, encoded.len()) };
        Some(encoded.len() as isize)
    }));
    match result {
        Ok(Some(length)) => length,
        Ok(None) => -2,
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn king_native_core_abi_version() -> u32 {
    1
}

#[cfg(test)]
mod tests {
    use super::{expand_range_batch, king_expand_range_batch};
    use std::ffi::CString;

    #[test]
    fn ipv4_cidr_batches_preserve_cursor_order() {
        let (a, c) = expand_range_batch("192.0.2.0/30", "0", 3).unwrap();
        assert_eq!(a, vec!["192.0.2.0", "192.0.2.1", "192.0.2.2"]);
        assert_eq!(c, "3");
        let (a, c) = expand_range_batch("192.0.2.0/30", &c, 3).unwrap();
        assert_eq!(a, vec!["192.0.2.3"]);
        assert_eq!(c, "0");
    }

    #[test]
    fn ipv4_window_wraps_like_dart() {
        let (a, c) = expand_range_batch("192.0.2.0/30", "3", 2).unwrap();
        assert_eq!(a, vec!["192.0.2.3", "192.0.2.0"]);
        assert_eq!(c, "1");
    }

    #[test]
    fn ipv6_cidr_batches_match_dart() {
        let (a, c) = expand_range_batch("2001:db8::/126", "0", 2).unwrap();
        assert_eq!(a, vec!["2001:db8::", "2001:db8::1"]);
        assert_eq!(c, "2");
        let (a, c) = expand_range_batch("2001:db8::/126", &c, 2).unwrap();
        assert_eq!(a, vec!["2001:db8::2", "2001:db8::3"]);
        assert_eq!(c, "0");
    }

    #[test]
    fn ipv6_large_cursor_is_lossless() {
        let (a, c) = expand_range_batch("2001:db8::/64", "18446744073709551617", 2).unwrap();
        assert_eq!(a.len(), 2);
        assert_eq!(c, "3");
    }

    #[test]
    fn descending_ranges_are_normalized() {
        let (a, c) = expand_range_batch("192.0.2.3-192.0.2.1", "0", 8).unwrap();
        assert_eq!(a, vec!["192.0.2.1", "192.0.2.2", "192.0.2.3"]);
        assert_eq!(c, "0");
    }

    #[test]
    fn single_address_emits_once() {
        let (a, c) = expand_range_batch("2001:db8::5", "0", 4).unwrap();
        assert_eq!(a, vec!["2001:db8::5"]);
        assert_eq!(c, "0");
    }

    #[test]
    fn full_ipv6_span_does_not_overflow() {
        let (a, c) = expand_range_batch("::/0", "0", 2).unwrap();
        assert_eq!(a, vec!["::", "::1"]);
        assert_eq!(c, "2");
        let (a, c) = expand_range_batch(
            "::/0",
            "340282366920938463463374607431768211455",
            2,
        )
        .unwrap();
        assert_eq!(a, vec!["ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"]);
        assert_eq!(c, "0");
    }

    #[test]
    fn rejects_invalid_prefix_and_mixed_families() {
        assert!(expand_range_batch("192.0.2.1/33", "0", 2).is_none());
        assert!(expand_range_batch("192.0.2.1-2001:db8::1", "0", 2).is_none());
        assert!(expand_range_batch("not-an-ip", "0", 2).is_none());
    }
}
