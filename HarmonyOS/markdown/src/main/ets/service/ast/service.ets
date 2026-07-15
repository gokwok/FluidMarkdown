// Copyright 2025 The FluidMarkdown Authors. All rights reserved.
// Use of this source code is governed by a Apache 2.0 license that can be
// found in the LICENSE file.

import {
  type MarkdownIt, markdown,
  plugin_footnote, plugin_emoji, plugin_sub, plugin_sup, plugin_taskList, plugin_katex,
  type IPluginKatexOption, type IPluginTaskListOption, type Token,
} from './markdown-it';
import { Program, Node, ENode, ELayout, Code, StyledContent, Fragment } from './node';
import { StyledTextValue } from '../../render/styled/styled-value';
import type { StyledValue } from '../../render/styled/styled-value';
import { EService, Service } from '../../engine/service';
import { Plugin } from '../../engine/plugin';
import type { Engine } from '../../engine';
import { CssService } from '../css';
import type { Declaration, Rule } from '../css/csstree';
import { newLog } from '../../util';

const log = newLog('AstService');
const PLAIN_CODE_CHUNK_MAX_LINES: number = 12;
const PLAIN_CODE_CHUNK_MAX_CHARS: number = 1024;

interface MarkdownFence {
  marker: string;
  length: number;
  tail: string;
}

function markdownFence(line: string): MarkdownFence | undefined {
  let start: number = 0;
  while (start < line.length && line.charAt(start) === ' ') {
    start += 1;
  }
  if (start > 3 || start >= line.length) {
    return undefined;
  }
  const marker: string = line.charAt(start);
  if (marker !== '`' && marker !== '~') {
    return undefined;
  }
  let end: number = start;
  while (end < line.length && line.charAt(end) === marker) {
    end += 1;
  }
  if (end - start < 3) {
    return undefined;
  }
  return { marker, length: end - start, tail: line.substring(end) };
}

function splitTableCells(line: string): string[] {
  const cells: string[] = [];
  let current: string = '';
  let backslashCount: number = 0;
  for (let index: number = 0; index < line.length; index += 1) {
    const char: string = line.charAt(index);
    if (char === '|' && backslashCount % 2 === 0) {
      cells.push(current);
      current = '';
    } else {
      current += char;
    }
    backslashCount = char === '\\' ? backslashCount + 1 : 0;
  }
  cells.push(current);
  if (cells.length > 0 && cells[0].trim().length === 0) {
    cells.shift();
  }
  if (cells.length > 0 && cells[cells.length - 1].trim().length === 0) {
    cells.pop();
  }
  return cells;
}

function tableHeaderColumnCount(line: string): number {
  if (line.indexOf('|') < 0) {
    return 0;
  }
  const cells: string[] = splitTableCells(line.trim());
  for (let index: number = 0; index < cells.length; index += 1) {
    if (/[^\s:\-]/.test(cells[index])) {
      return cells.length;
    }
  }
  return 0;
}

function normalizedTableDelimiter(line: string, columnCount: number): string | undefined {
  const leadingLength: number = line.length - line.trimStart().length;
  const trailingLength: number = line.length - line.trimEnd().length;
  const leading: string = line.substring(0, leadingLength);
  const trailing: string = trailingLength > 0 ? line.substring(line.length - trailingLength) : '';
  const value: string = line.trim();
  if (value.length === 0) {
    return undefined;
  }
  const hasLeadingPipe: boolean = value.startsWith('|');
  const hasTrailingPipe: boolean = value.endsWith('|');
  const cells: string[] = value.split('|');
  if (hasLeadingPipe) {
    cells.shift();
  }
  if (hasTrailingPipe) {
    cells.pop();
  }
  if (cells.length === 0) {
    return undefined;
  }
  for (let index: number = 0; index < cells.length; index += 1) {
    const cell: string = cells[index].trim();
    if (!/^:?-+:?$/.test(cell)) {
      return undefined;
    }
    cells[index] = cell;
  }
  if (cells.length === columnCount) {
    return line;
  }
  if (cells.length > columnCount) {
    cells.splice(columnCount);
  } else {
    while (cells.length < columnCount) {
      cells.push('---');
    }
  }
  return `${leading}${hasLeadingPipe ? '|' : ''}${cells.join('|')}${hasTrailingPipe ? '|' : ''}${trailing}`;
}

export function normalizeTableDelimiterColumns(content: string): string {
  if (content.indexOf('|') < 0) {
    return content;
  }
  const lines: string[] = content.split('\n');
  let activeFence: MarkdownFence | undefined = undefined;
  for (let index: number = 0; index < lines.length; index += 1) {
    const fence: MarkdownFence | undefined = markdownFence(lines[index]);
    if (activeFence !== undefined) {
      if (fence !== undefined && fence.marker === activeFence.marker &&
        fence.length >= activeFence.length && fence.tail.trim().length === 0) {
        activeFence = undefined;
      }
      continue;
    }
    if (fence !== undefined) {
      activeFence = fence;
      continue;
    }
    if (index === 0) {
      continue;
    }
    if (lines[index].indexOf('|') < 0) {
      continue;
    }
    const columnCount: number = tableHeaderColumnCount(lines[index - 1]);
    if (columnCount === 0) {
      continue;
    }
    const normalized: string | undefined = normalizedTableDelimiter(lines[index], columnCount);
    if (normalized !== undefined) {
      lines[index] = normalized;
    }
  }
  return lines.join('\n');
}

export function splitPlainCodeContent(content: string): string[] {
  if (content.length === 0) {
    return [''];
  }
  const lines: string[] = content.split('\n');
  const chunks: string[] = [];
  let chunkLines: string[] = [];
  let chunkLength: number = 0;
  for (let index: number = 0; index < lines.length; index += 1) {
    const line: string = lines[index];
    const addedLength: number = line.length + (chunkLines.length > 0 ? 1 : 0);
    if (chunkLines.length > 0 &&
      (chunkLines.length >= PLAIN_CODE_CHUNK_MAX_LINES ||
        chunkLength + addedLength > PLAIN_CODE_CHUNK_MAX_CHARS)) {
      chunks.push(chunkLines.join('\n'));
      chunkLines = [];
      chunkLength = 0;
    }
    chunkLines.push(line);
    chunkLength += line.length + (chunkLines.length > 1 ? 1 : 0);
  }
  if (chunkLines.length > 0) {
    chunks.push(chunkLines.join('\n'));
  }
  return chunks;
}

export interface IResult {
  program: Program;
  content?: string;
}

// markdown-it 构造（含 katex/emoji/footnote 插件注册与正则编译）约 10ms，
// parse 同步且无跨调用状态，全部实例共享一份即可。
let sharedMarkdownIt: MarkdownIt | undefined;
function obtainSharedMarkdownIt(): MarkdownIt {
  if (!sharedMarkdownIt) {
    const markdown_it = new markdown() as MarkdownIt;
    markdown_it.set({ html: true });
    markdown_it.disable(['html_block']);  // only support inline html

    const plugins = [
      plugin_footnote,
      plugin_emoji,
      plugin_sub,
      plugin_sup,
    ];
    plugins.forEach(ele => markdown_it.use(ele));

    markdown_it.use<IPluginTaskListOption>(plugin_taskList, { enabled: true });
    markdown_it.use<IPluginKatexOption>(plugin_katex, { throwOnError: false });
    sharedMarkdownIt = markdown_it;
  }
  return sharedMarkdownIt;
}

export class AstService extends Service {
  private static gid: number = 0;
  readonly ID: number = AstService.gid++;
  readonly type: EService = EService.AST;
  private tail: Promise<IResult | void> = Promise.resolve();
  private count: number = 0;
  private plugins: AstServicePlugin[] = [];
  private markdown_it: MarkdownIt;
  constructor(engine?: Engine) {
    super(engine);
    this.markdown_it = obtainSharedMarkdownIt();
  }
  add<T extends Plugin = AstServicePlugin>(plugin: T): void {
    if (plugin instanceof AstServicePlugin) {
      this.plugins.push(plugin);
    } else {
      log.e(`${this.ID} add plugin error, not AstServicePlugin`);
    }
  }
  private get parsePlugin(): AstServicePlugin<IAstPluginParse> | undefined {
    return this.plugins.filter(ele => ele.type === EAstPlugin.Parse).pop();
  }
  parse(content: string): Promise<IResult> {
    this.count++;
    const tail = this.tail.then(async () => {
      this.parsePlugin?.handler?.willParse?.(content);

      const tokens = this.markdown_it.parse(normalizeTableDelimiterColumns(content), new Object());
      const result: IResult = this.buildResult(content, tokens);

      this.parsePlugin?.handler?.didParse?.(result);

      return result;
    }).finally(() => {
      this.count--;
    });
    this.tail = tail;
    return tail;
  }
  parseWithStablePrefix(content: string, prefixTokens: Token[], tailContent: string,
    tailLineOffset: number): Promise<IResult> {
    this.count++;
    const tail = this.tail.then(async () => {
      this.parsePlugin?.handler?.willParse?.(content);
      const tailTokens: Token[] = this.markdown_it.parse(normalizeTableDelimiterColumns(tailContent), new Object());
      this.offsetTokenMaps(tailTokens, tailLineOffset);
      const tokens: Token[] = prefixTokens.slice().concat(tailTokens);
      const result: IResult = this.buildResult(content, tokens);
      this.parsePlugin?.handler?.didParse?.(result);
      return result;
    }).finally(() => {
      this.count--;
    });
    this.tail = tail;
    return tail;
  }
  get processing(): boolean {
    return this.count > 0;
  }
  private buildResult(content: string, tokens: Token[]): IResult {
    const program = new Program(tokens, {
      engine: () => this.engine,
    });
    this.prepareFragment(program);
    program.document.createHash();
    this.prepareCodeBlock(program);
    return { program, content };
  }
  private offsetTokenMaps(tokens: Token[], lineOffset: number): void {
    for (let index = 0; index < tokens.length; index += 1) {
      const token: Token = tokens[index];
      if (token.map !== null) {
        token.map = [token.map[0] + lineOffset, token.map[1] + lineOffset];
      }
      if (token.children !== null && token.children !== undefined) {
        this.offsetTokenMaps(token.children, lineOffset);
      }
    }
  }
  toHtml(node: Node): string {
    const tokens: Token[] = [];
    const document = node.document;
    if (document) {
      const startToken = node.token;
      const endToken = node.next?.deref()?.token;
      const pick = (from: number, list: Token[]) => {
        for (let index = from; index < list.length; index++) {
          if (list[index] === endToken) {
            break;
          }
          tokens.push(list[index]);
        }
      };
      const traver = (list: Token[]): boolean => {
        for (let index = 0; index < list.length; index++) {
          const token = list[index];
          if (token === startToken) {
            pick(index, list);
            return true;
          } else {
            if (traver(token.children || [])) {
              return true;
            }
          }
        }
        return false;
      }
      if (startToken) {
        traver(document.tokens || []);
      }
    }
    return this.markdown_it.renderer.render(tokens, this.markdown_it.options, new Object());
  }
  private prepareFragment(program: Program) {
    if (!this.engine?.deref()?.ctx?.fragmentEnable) {
      log.i(`${this.ID} ast fragment is disabled`);
      return;
    }
    const blockMax = Number(this.engine?.deref()?.ctx?.fragmentBlockMax) || 10;
    const ignoreNodes: ENode[] = [ ENode.FootnoteDef ];
    log.i(`${this.ID} will prepare ast fragment. blockMax: ${this.engine?.deref()?.ctx?.fragmentBlockMax}`);
    const fragments: Fragment[] = [];
    let currentFragment: Fragment | undefined = undefined;
    let currentBlockCount: number = 0;
    const createFragment = (): Fragment => {
      const fragment = new Fragment();
      fragments.push(fragment);
      return fragment;
    };
    let node = program.document.first?.deref();
    while (node) {
      if (isStandaloneEmbedBlock(node)) {
        const fragment: Fragment = createFragment();
        fragment.append(node);
        currentFragment = undefined;
        currentBlockCount = 0;
      } else {
        const isCountedBlock: boolean = node.layout === ELayout.Block && !ignoreNodes.includes(node.type);
        if (currentFragment === undefined || (isCountedBlock && currentBlockCount >= blockMax)) {
          currentFragment = createFragment();
          currentBlockCount = 0;
        }
        currentFragment.append(node);
        if (isCountedBlock) {
          currentBlockCount += 1;
        }
      }
      node = program.document.first?.deref();
    }
    fragments.forEach(ele => {
      // Fragment 包装节点只被 document 的 WeakRef 链接（first/last/parent）引用，
      // 必须加入 program.nodes 强引用，否则 GC 回收后 document.children 变空，
      // 渲染端（FragmentComponent）拿到的 document 没有任何子节点。
      program.nodes.push(ele);
      program.document.append(ele);
    });
    log.i(`${this.ID} did prepare ast fragment. fragments: ${fragments.length}`);
  }
  private prepareCodeBlock(program: Program) {
    const codeTheme = this.engine?.deref()?.theme?.theme.code;
    const highlightEnabled = codeTheme?.highlight !== false;
    const codeFontSize = codeTheme?.font?.fontSize?.value ?? 13;
    // 关闭高亮时正文统一应用主题基础字体（族/字号/颜色）；
    // 开启高亮时颜色由内联 CSS 控制，基础样式不下发以免覆盖。
    const baseStyles: StyledValue[] | undefined =
      !highlightEnabled && codeTheme?.font !== undefined ? [new StyledTextValue(codeTheme.font)] : undefined;
    const codes: Code[] = [];
    Node.traverse(program.document, {
      on: node => {
        codes.push(node as Code);
        return true;
      },
      filter: node => {
        return node.type === ENode.Code && node.layout === ELayout.Block;
      },
    });
    for (const code of codes) {
      if (code.content) {
        if (!highlightEnabled) {
          const styleKey: string = JSON.stringify(codeTheme?.font ?? {});
          const chunks: string[] = splitPlainCodeContent(code.content);
          for (let index: number = 0; index < chunks.length; index += 1) {
            const styled = new StyledContent();
            styled.styled = this.engine?.deref()?.code?.styledFromText(chunks[index], baseStyles, styleKey);
            if (styled.styled !== undefined) {
              styled.createHash();
              program.nodes.push(styled);
              code.append(styled);
            }
          }
          continue;
        }
        const page = this.engine?.deref()?.code?.parse4page(code.content, { language: code.language || '' });
        if (page) {
          const html = this.engine?.deref()?.html?.parse(page);
          const css = this.engine?.deref()?.code?.css;
          if (html && css) {
            if (highlightEnabled) {
              this.engine?.deref()?.html?.traverse(html, {
                on: htmlNode => {
                  const element = this.engine?.deref()?.html?.toElement(htmlNode);
                  if (element) {
                    const cls = element.attribs['class']?.split(' ').filter(ele => ele.length > 0) || [];
                    if (cls && cls.length > 0) {
                      let style = element.attribs['style'] ? `${element.attribs['style']};` : '';
                      CssService.findAll<Rule>(css, rule => {
                        return rule.type === 'Rule';
                      }).forEach(rule => {
                        const matched = CssService.find(rule.prelude, prelude => {
                          if (prelude.type === 'ClassSelector') {
                            return cls.indexOf(prelude.name) !== -1;
                          }
                          return false;
                        });
                        if (matched) {
                          CssService.findAll<Declaration>(rule.block, block => {
                            return block.type === 'Declaration';
                          }).forEach(declaration => {
                            style = `${style} ${declaration.property}: ${CssService.generate(declaration.value)};`;
                          });
                        }
                      });
                      if (style.length > 0) {
                        element.attribs['style'] = `${style} font-size: ${codeFontSize};`;
                      }
                    }
                  }
                  return true;
                },
              });
            }
            const adapted = this.engine?.deref()?.html?.render(html);
            if (adapted && adapted.length > 0) {
              const styled = new StyledContent();
              styled.createHash();
              styled.styled = this.engine?.deref()?.code?.styledFromHtml(adapted, baseStyles);
              program.nodes.push(styled);
              code.append(styled);
            }
          }
        }
      }
    }
  }
}

export function isStandaloneEmbedBlock(node: Node): boolean {
  return node.type === ENode.Table || (node.type === ENode.Code && node.layout === ELayout.Block);
}

export interface IFragment {
  enable?: boolean;
  blockMax?: number;
}

export enum EAstPlugin {
  Unknown = 'unknown',
  Parse = 'parse',
}
export interface IAstPlugin {}
export interface IAstPluginParse extends IAstPlugin {
  willParse?: (content: string) => void;
  didParse?: (result: IResult) => void;
}
export abstract class AstServicePlugin <
  T extends IAstPlugin = IAstPlugin,
> extends Plugin {
  abstract readonly type: EAstPlugin;
  abstract readonly handler: T;
}

// export { Program, Node };
