// Copyright 2025 The FluidMarkdown Authors. All rights reserved.
// Use of this source code is governed by a Apache 2.0 license that can be
// found in the LICENSE file.

import { K_COMPONENT, MDLength, MDMargin } from '../../util';
import { Engine } from '../../engine';
import { ITheme } from '../../theme';
import { image } from '@kit.ImageKit';

@Builder
export function ContentBoxEmptyActions() {
}

@ComponentV2
export struct ContentBoxComponent {
  @Consumer(K_COMPONENT.THEME) theme: ITheme = {};
  @BuilderParam content: () => void;
  // 宿主可注入自定义动作区（如带 hover/tooltip/复制反馈的按钮），
  // hasCustomActions 为 true 时优先于 bar.actions 图标列表。
  @BuilderParam actionsBuilder: () => void = ContentBoxEmptyActions;
  @Param hasCustomActions: boolean = false;
  @Require @Param bar: IContentBoxBar;
  @Event onActionClick?: (action: IContentBoxAction, event: ClickEvent) => void = undefined;

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
  }

  private hasBar(): boolean {
    return !!((this.bar.title?.length ?? 0) > 0 || (this.bar.actions?.length ?? 0) > 0 || this.hasCustomActions);
  }

  build() {
    Column() {
      if (this.hasBar()) {
        //  bar
        Row() {
          Text(this.bar.title)
            .fontColor(this.theme.contentBox?.barFont?.fontColor)
            .fontSize(this.theme.contentBox?.barFont?.fontSize?.value)
            .fontWeight(this.theme.contentBox?.barFont?.fontWeight)
            .margin(this.theme.contentBox?.barMargin ? MDMargin.lengthMargin(this.theme.contentBox?.barMargin) : undefined)
          Row() {
            if (this.hasCustomActions) {
              this.actionsBuilder()
            } else {
              ForEach(this.bar.actions ?? [], (action: IContentBoxAction) => {
                Image(action.icon)
                  .width(MDLength.metrics2length(this.theme.contentBox?.barActionIconWidth ?? MDLength.vp(0)))
                  .height(MDLength.metrics2length(this.theme.contentBox?.barActionIconHeight ?? MDLength.vp(0)))
                  .margin({ left: 10 })
                  .onClick(event => this.onActionClick?.(action, event))
              })
            }
          }
          .margin(this.theme.contentBox?.barMargin ? MDMargin.lengthMargin(this.theme.contentBox?.barMargin) : undefined)
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .padding(this.theme.contentBox?.barPadding ? MDMargin.lengthMargin(this.theme.contentBox?.barPadding) : undefined)
        .backgroundColor(this.theme.contentBox?.barBackgroundColor)
        .border({
          radius: {
            topLeft: this.theme.contentBox?.border?.radius?.value ? this.theme.contentBox?.border?.radius?.value - 1 : undefined,
            topRight: this.theme.contentBox?.border?.radius?.value ? this.theme.contentBox?.border?.radius?.value - 1 : undefined,
          },
        })
        .clip(true)
      }

      //  content
      Scroll(this.scroller) {
        this.content()
      }
      .scrollable(ScrollDirection.Horizontal)
    }
    .backgroundColor(this.theme.contentBox?.backgroundColor)
    .border({
      width: MDLength.metrics2length(this.theme.contentBox?.border?.width ?? MDLength.vp(0)),
      color: this.theme.contentBox?.border?.color,
      radius: MDLength.metrics2length(this.theme.contentBox?.border?.radius ?? MDLength.vp(0)),
      style: BorderStyle.Solid,
    })
    .clip(true)
  }
}
export interface IContentBoxBar {
  title?: string;
  actions?: IContentBoxAction[];
  /** 自定义动作区，提供时优先于 actions 图标列表。 */
  actionsBuilder?: () => void;
}
export interface IContentBoxAction {
  icon?: image.PixelMap;
  tag?: string | EContentBoxAction;
}
export enum EContentBoxAction {
  Open = 'open',
  Copy = 'copy',
}
export abstract class ContentBoxBar {
  static openAction(option?: IContentBoxAction, engine?: Engine): IContentBoxAction {
    return {
      icon: option?.icon ?? engine?.image?.load('icon_open.png')?.createPixelMapSync(),
      tag: option?.tag ?? EContentBoxAction.Open,
    };
  }
  static copyAction(option?: IContentBoxAction, engine?: Engine): IContentBoxAction {
    return {
      icon: option?.icon ?? engine?.image?.load('icon_copy.png')?.createPixelMapSync(),
      tag: option?.tag ?? EContentBoxAction.Copy,
    };
  }
}