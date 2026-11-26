from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_king_ai_research_storage_is_append_only_and_streamed():
    source = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
    policy = (ROOT / 'lib' / 'king_ai_research_policy.dart').read_text(encoding='utf-8')
    remember = source.split('Future<void> _rememberResearch(', 1)[1].split(
        'Future<List<Map<String, String>>> _relevantResearchMemory(', 1
    )[0]
    retrieve = source.split('Future<List<Map<String, String>>> _relevantResearchMemory(', 1)[1].split(
        'Future<List<String>> _selectRelevantPaths(', 1
    )[0]

    assert 'FileMode.append' in remember
    assert 'readAsLines' not in remember
    assert 'mergeKingAiResearchMemory' not in remember
    assert 'openRead()' in retrieve
    assert 'rankKingAiResearchMemoryStream' in retrieve
    assert 'await for (final line in lines)' in policy


def test_streaming_research_policy_keeps_memory_usage_independent_of_history_size():
    policy = (ROOT / 'lib' / 'king_ai_research_policy.dart').read_text(encoding='utf-8')
    function = policy.split('Future<List<Map<String, String>>> rankKingAiResearchMemoryStream(', 1)[1]
    function = function.split('\\n}\\n', 1)[0]
    assert 'await for (final line in lines)' in function
    assert 'ranked.length > limit' in function
    assert 'readAsLines' not in function
