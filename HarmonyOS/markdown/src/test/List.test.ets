import local from './LocalUnit.test';
import incrementalMarkdownTest from './IncrementalMarkdown.test';

export default function testsuite() {
  local();
  incrementalMarkdownTest();
}
