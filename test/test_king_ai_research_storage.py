from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class KingAiResearchStorageTests(unittest.TestCase):
    def test_research_storage_is_append_only_and_streamed(self):
        source = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        policy = (ROOT / 'lib' / 'king_ai_research_policy.dart').read_text(encoding='utf-8')
        remember = source.split('Future<void> _rememberResearch(', 1)[1].split(
            'Future<List<Map<String, String>>> _relevantResearchMemory(', 1
        )[0]
        retrieve = source.split('Future<List<Map<String, String>>> _relevantResearchMemory(', 1)[1].split(
            'Future<List<String>> _selectRelevantPaths(', 1
        )[0]

        self.assertIn('FileMode.append', remember)
        self.assertIn('FileLock.exclusive', remember)
        self.assertIn('file.path}.lock', remember)
        self.assertNotIn('readAsLines', remember)
        self.assertNotIn('mergeKingAiResearchMemory', remember)
        self.assertIn('openRead()', retrieve)
        self.assertIn('rankKingAiResearchMemoryStream', retrieve)
        self.assertIn('await for (final line in lines)', policy)

    def test_streaming_research_memory_usage_is_independent_of_history_size(self):
        policy = (ROOT / 'lib' / 'king_ai_research_policy.dart').read_text(encoding='utf-8')
        function = policy.split(
            'Future<List<Map<String, String>>> rankKingAiResearchMemoryStream(', 1
        )[1].split('\\n}\\n', 1)[0]
        self.assertIn('await for (final line in lines)', function)
        self.assertIn('ranked.length > limit', function)
        self.assertNotIn('readAsLines', function)


if __name__ == '__main__':
    unittest.main()
