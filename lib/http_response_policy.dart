/// A remote configuration/list source is usable only when the HTTP
/// request succeeded and returned a non-empty body.
bool isUsableHttpListResponse(int statusCode, String body) =>
    statusCode == 200 && body.trim().isNotEmpty;
