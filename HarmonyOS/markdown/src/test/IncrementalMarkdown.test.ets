import { describe, expect, it } from '@ohos/hypium';
import { findIncrementalMarkdownSplit } from '../main/ets/service/ast/incremental';
import { normalizeTableDelimiterColumns, splitPlainCodeContent } from '../main/ets/service/ast/service';

function plainBlocks(count: number): string {
  const blocks: string[] = [];
  for (let index = 0; index < count; index += 1) {
    blocks.push(`第 ${index} 段稳定正文，包含足够长度用于增量解析边界验证。`);
  }
  return blocks.join('\n\n');
}

export default function incrementalMarkdownTest() {
  describe('Incremental markdown split', () => {
    it('keeps a bounded tail for long closed top-level blocks', 0, () => {
      const content: string = plainBlocks(220);
      const split: number = findIncrementalMarkdownSplit(content);

      expect(split > 0).assertTrue();
      expect(content.substring(split).length >= 3000).assertTrue();
      expect(content.substring(0, split).endsWith('\n\n')).assertTrue();
    });

    it('falls back to a full parse when reference definitions affect earlier blocks', 0, () => {
      const content: string = `${plainBlocks(180)}\n\n[fluid]: https://example.com\n\n使用 [链接][fluid]`;
      expect(findIncrementalMarkdownSplit(content)).assertEqual(-1);
    });

    it('keeps complete list, setext, and blockquote structures in the reparsed tail', 0, () => {
      const suffix = [
        '- 列表一',
        '- 列表二',
        '',
        '集合式标题',
        '=========',
        '',
        '> 引用第一行',
        '> 引用第二行',
      ].join('\n');
      const content: string = `${plainBlocks(180)}\n\n${suffix}`;
      const split: number = findIncrementalMarkdownSplit(content);
      const tail: string = split > 0 ? content.substring(split) : content;

      expect(tail.indexOf('- 列表一') >= 0).assertTrue();
      expect(tail.indexOf('集合式标题\n=========') >= 0).assertTrue();
      expect(tail.indexOf('> 引用第一行') >= 0).assertTrue();
    });

    it('does not split inside a fenced code block', 0, () => {
      const content: string = `${plainBlocks(120)}\n\n\`\`\`ts\n${plainBlocks(100)}\n\`\`\``;
      const split: number = findIncrementalMarkdownSplit(content);
      const prefix: string = split > 0 ? content.substring(0, split) : '';
      const fenceCount: number = prefix.split('```').length - 1;

      expect(fenceCount % 2).assertEqual(0);
    });

    it('does not close a four-backtick fence with three backticks', 0, () => {
      const content: string = [
        plainBlocks(120),
        '````md',
        '```',
        '',
        plainBlocks(140),
        '````',
        plainBlocks(20),
      ].join('\n\n');
      const split: number = findIncrementalMarkdownSplit(content);
      const opening: number = content.indexOf('````md');
      const closing: number = content.lastIndexOf('````');

      expect(split <= opening || split > closing).assertTrue();
    });

    it('keeps tilde and backtick fence state separate', 0, () => {
      const content: string = [
        plainBlocks(120),
        '~~~text',
        '```',
        '',
        plainBlocks(140),
        '~~~',
        plainBlocks(20),
      ].join('\n\n');
      const split: number = findIncrementalMarkdownSplit(content);
      const opening: number = content.indexOf('~~~text');
      const closing: number = content.lastIndexOf('~~~');

      expect(split <= opening || split > closing).assertTrue();
    });

    it('allows a longer matching fence to close a shorter fence', 0, () => {
      const content: string = [
        plainBlocks(120),
        '```text',
        plainBlocks(80),
        '````',
        plainBlocks(120),
      ].join('\n\n');
      const split: number = findIncrementalMarkdownSplit(content);
      const opening: number = content.indexOf('```text');
      const closing: number = content.indexOf('````', opening);

      expect(split <= opening || split > closing).assertTrue();
    });

    it('does not treat a fence indented by four spaces as a top-level fence', 0, () => {
      const indentedBlock: string = [
        '    ```text',
        '    indented code',
        '',
        '    still indented code',
      ].join('\n');
      const content: string = `${plainBlocks(140)}\n\n${indentedBlock}\n\n${plainBlocks(120)}`;
      const split: number = findIncrementalMarkdownSplit(content);
      const opening: number = content.indexOf('    ```text');
      const end: number = opening + indentedBlock.length;

      expect(split <= opening || split > end).assertTrue();
    });

    it('keeps completed plain-code chunks stable while the tail grows', 0, () => {
      const lines: string[] = [];
      for (let index: number = 0; index < 80; index += 1) {
        lines.push(`const value${index}: number = ${index};`);
      }
      const before: string = lines.join('\n');
      const beforeChunks: string[] = splitPlainCodeContent(before);
      const after: string = `${before}\nconst tail: string = 'done';`;
      const afterChunks: string[] = splitPlainCodeContent(after);

      expect(beforeChunks.length > 1).assertTrue();
      expect(afterChunks.length >= beforeChunks.length).assertTrue();
      expect(afterChunks[0]).assertEqual(beforeChunks[0]);
      expect(afterChunks.join('\n')).assertEqual(after);
    });

    it('aligns malformed table delimiters with the header column count', 0, () => {
      const extraColumn: string = '| A | B |\n|---|---|---|\n| 1 | 2 |\n';
      const missingColumn: string = '| A | B | C |\n|:---|---:|\n| 1 | 2 | 3 |\n';

      expect(normalizeTableDelimiterColumns(extraColumn))
        .assertEqual('| A | B |\n|---|---|\n| 1 | 2 |\n');
      expect(normalizeTableDelimiterColumns(missingColumn))
        .assertEqual('| A | B | C |\n|:---|---:|---|\n| 1 | 2 | 3 |\n');
    });

    it('leaves table-like fenced code unchanged', 0, () => {
      const content: string = '```md\n| A | B |\n|---|---|---|\n```';
      expect(normalizeTableDelimiterColumns(content)).assertEqual(content);
    });

    it('preserves setext headings and horizontal rules', 0, () => {
      const setext: string = 'A | B\n---\n';
      const horizontalRule: string = '正文含有 A | B\n\n---\n';

      expect(normalizeTableDelimiterColumns(setext)).assertEqual(setext);
      expect(normalizeTableDelimiterColumns(horizontalRule)).assertEqual(horizontalRule);
    });

    it('preserves escaped pipes and already aligned tables', 0, () => {
      const escapedPipe: string = '| A \\| B | C |\n|---|---|\n| 1 | 2 |\n';
      const aligned: string = '| A | B |\n|:---|---:|\n| 1 | 2 |\n';

      expect(normalizeTableDelimiterColumns(escapedPipe)).assertEqual(escapedPipe);
      expect(normalizeTableDelimiterColumns(aligned)).assertEqual(aligned);
    });
  });
}
