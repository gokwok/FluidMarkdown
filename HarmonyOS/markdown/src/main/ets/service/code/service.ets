// Copyright 2025 The FluidMarkdown Authors. All rights reserved.
// Use of this source code is governed by a Apache 2.0 license that can be
// found in the LICENSE file.

import { hl, type HighlightOptions, type HighlightResult } from './highlightjs';
import { EService, Service } from '../../engine/service';
import { Plugin } from '../../engine/plugin';
import { HIGHLIGHT_DEFAULT_CSS } from './style';
import { type CssNode  } from '../css';
import type { StyledValue } from '../../render/styled/styled-value';

export class CodeService extends Service {
  private _css?: CssNode;
  private plainStyledCache: Map<string, StyledString> = new Map<string, StyledString>();
  readonly type: EService = EService.Code;
  add<T extends Plugin>(_plugin: T): void {
  }
  parse(content: string, option: HighlightOptions): HighlightResult | undefined {
    try {
      return hl.getLanguage(option.language || '') ? hl.highlight(content, option) : hl.highlightAuto(content);
    } catch (e) {
      return undefined;
    }
  }
  parse4page(content: string, option: HighlightOptions): string | undefined {
    const value = this.parse(content, option)?.value;
    if (value) {
      return `<span class="hljs">${value}</span>`;
    }
    return undefined;
  }
  get css() {
    if (!this._css) {
      this._css = this.engine?.deref()?.css?.parse(HIGHLIGHT_DEFAULT_CSS).data;
    }
    return this._css;
  }
  styledFromHtml(content: string, baseStyles?: StyledValue[]): StyledString | undefined {
    return this.engine?.deref()?.html?.toStyled(content, baseStyles);
  }
  styledFromText(content: string, baseStyles?: StyledValue[], styleKey: string = ''): StyledString | undefined {
    const cacheKey: string = `${styleKey}:${content}`;
    const cached: StyledString | undefined = this.plainStyledCache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }
    const escaped: string = content
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
    const styled: StyledString | undefined = this.engine?.deref()?.html?.toStyled(escaped, baseStyles);
    if (styled !== undefined) {
      if (this.plainStyledCache.size >= 128) {
        for (const oldest of this.plainStyledCache.keys()) {
          this.plainStyledCache.delete(oldest);
          break;
        }
      }
      this.plainStyledCache.set(cacheKey, styled);
    }
    return styled;
  }
}
