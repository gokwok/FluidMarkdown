// Copyright 2025 The FluidMarkdown Authors. All rights reserved.
// Use of this source code is governed by a Apache 2.0 license that can be
// found in the LICENSE file.

import { K_COMPONENT, MDLength, IMDArea, newLog, MDMargin, MDArea } from '../../util';
import { Engine, BaseEngine } from '../../engine';
import { ITheme } from '../../theme';
import {
  Styled, StyledObject, StyledEmbed, StyledTextValue, type StyledValue,
  EStyledObject, EStyledObjectEvent, type IStyledObjectAppendEvent,
} from '../styled';
import { ENode, TableItem, ETableItem } from '../../service/ast/node';
import { EmbedComponent } from './embed';
import { TextComponent } from './text';
import { ContentBoxComponent, ContentBoxBar, type IContentBoxAction, IContentBoxBar } from './content-box';

const log = newLog('TableComponent');
const log2 = newLog('FSTableComponent');

@ComponentV2
export struct FSTableComponent {
  private static gid: number = 0;
  private static createGid() {
    return FSTableComponent.gid++;
  }
  readonly ID: number = FSTableComponent.createGid();

  @Require @Param @Once styledEmbed: StyledEmbed;
  @Require @Param @Once engine: Engine = new BaseEngine();

  @Provider(K_COMPONENT.THEME) theme: ITheme = this.engine.theme!.theme;
  @Provider(K_COMPONENT.SHARED_ENGINE) sharedEngine: Engine = this.engine;

  @Local table: DSTable = new DSTable();
  @Local ready: boolean = false
  @Local uiArea?: Area;

  @Monitor('uiArea') onUIAreaChange(monitor: IMonitor) {
    const value = monitor.value<Area>();
    if (value?.before === undefined && value?.now !== undefined) {
      this.reload();
    }
  }

  private get node() {
    const node = this.styledEmbed.node;
    if (!node || !node.is(ENode.Table)) {
      log2.e(`current embed node is not table: ${node?.type}`);
      return undefined;
    }
    return node;
  }

  private reload() {
    const tableNode = this.node;
    if (tableNode) {
      const dequeueRow = (rowIndex: number, rowItem: TableItem) => {
        let row = this.table.rows[rowIndex];
        if (!row) {
          row = new DSTableRow(rowItem, this.table);
          this.table.rows.push(row);
        } else {
          row.node = new WeakRef(rowItem);
        }
        return row;
      };
      const dequeueCell = (row: DSTableRow, cellIndex: number, cellItem: TableItem) => {
        let cell = row.cells[cellIndex];
        if (!cell) {
          cell = new DSTableCell(row, cellItem, this.table);
          row.cells.push(cell);
        } else {
          cell.node = new WeakRef(cellItem);
        }
        return cell;
      };

      const rows: TableItem[] = [];
      tableNode.children.forEach(child => {
        //  thead | tbody
        child.children.forEach(item => {
          //  tr
          rows.push(item as TableItem);
        });
      });
      rows.forEach((row, rowIndex) => {
        const tableRow = dequeueRow(rowIndex, row as TableItem);
        row.children.forEach((cell, cellIndex) => {
          dequeueCell(tableRow, cellIndex, cell as TableItem);
        });
        if (tableRow.cells.length > row.children.length) {
          tableRow.cells.splice(row.children.length);
        }
      });
      if (this.table.rows.length > rows.length) {
        this.table.rows.splice(rows.length);
      }
    }
  }
  build() {
    Row() {
      this.FSTableContent()
    }
    .height("100%")
    .width("100%")
    .onAreaChange((_oldValue, newValue) => {
      this.uiArea = newValue;
      if (newValue.height < newValue.width) {
        this.ready = true
      }
    })
  }
  @Builder
  FSTableContent() {
    List() {
      ForEach(this.table.rows, (row: DSTableRow) => {
        if (row.parent?.itemType === ETableItem.Head) {
          //  Table TH
          ListItem() {
            this.FSTableRow({ row, styles: [new StyledTextValue(this.theme.table?.headerFont)] })
          }
          .backgroundColor(this.theme.table?.headerBackgroundColor)
        } else {
          //  Table TD
          ListItem() {
            this.FSTableRow({ row, styles: [new StyledTextValue(this.theme.table?.contentFont)] })
          }
        }
      }, (row: DSTableRow) => row.likelyKey)
    }
  }
  @Builder
  FSTableRow(data: ITableRowData) {
    Row() {
      ForEach(data.row.cells, (cell: DSTableCell) => {
        Row() {
          Scroll() {
            EmbedComponent({
              node: cell.node?.deref(),
              area: { width: this.theme.table?.cellMaxWidth },
              styles: data.styles,
            })
              .constraintSize(cell.constraintSize(this.uiArea ? MDArea.area(this.uiArea) : undefined, this.theme))
              .onAreaChange((oldValue, newValue) => {
                if (MDArea.mdAreaEqual(MDArea.area(oldValue), MDArea.area(newValue))) {
                  return;
                }
                cell.table?.deref()?.cellAreaChange(cell, oldValue, newValue);
              })
          }
          .align(Alignment.TopStart)
          .scrollable(ScrollDirection.None)
          .constraintSize({ minWidth: cell.width, minHeight: cell.height })
        }
        .padding(this.theme.contentBox?.barMargin ? MDMargin.lengthMargin(this.theme.contentBox?.barMargin) : undefined)
        .borderWidth(cell.borderWidth(this.theme))
        .borderColor(this.theme.contentBox?.border?.color)
      }, (cell: DSTableCell) => cell.likelyKey)
    }
  }
}

@ComponentV2
export struct TableComponent {
  private static gid: number = 0;
  private static createGid() {
    return TableComponent.gid++;
  }
  readonly ID: number = TableComponent.createGid();

  @Consumer(K_COMPONENT.THEME) theme: ITheme = {};
  @Consumer(K_COMPONENT.SHARED_ENGINE) sharedEngine: Engine = new BaseEngine();

  @Require @Param @Once styledEmbed: StyledEmbed;
  @Local table: DSTable = new DSTable();

  @Monitor('styledEmbed') onStyledEmbedChange(monitor: IMonitor) {
    const embed = monitor.value<StyledEmbed>();
    if (embed?.before || embed?.now) {
      if (embed?.before?.option.styled.node?.hash !== embed?.now?.option.styled.node?.hash) {
        this.reload();
      }
    }
  }

  private bridge: TableComponentBridge = new TableComponentBridge({
    styledEmbed: () => this.styledEmbed,
  });

  private barOption?: IContentBoxBar;
  private currentArea?: IMDArea;

  private get node() {
    const node = this.styledEmbed.node;
    if (!node || !node.is(ENode.Table)) {
      log.e(`component ${this.ID} current embed node is not table: ${node?.type}`);
      return undefined;
    }
    return node;
  }
  private reload() {
    const tableNode = this.node;
    if (tableNode) {
      const dequeueRow = (rowIndex: number, rowItem: TableItem) => {
        let row = this.table.rows[rowIndex];
        if (!row) {
          row = new DSTableRow(rowItem, this.table);
          this.table.rows.push(row);
        } else {
          row.node = new WeakRef(rowItem);
        }
        return row;
      };
      const dequeueCell = (row: DSTableRow, cellIndex: number, cellItem: TableItem) => {
        let cell = row.cells[cellIndex];
        if (!cell) {
          cell = new DSTableCell(row, cellItem, this.table);
          row.cells.push(cell);
        } else {
          cell.node = new WeakRef(cellItem);
        }
        return cell;
      };

      const rows: TableItem[] = [];
      tableNode.children.forEach(child => {
        //  thead | tbody
        child.children.forEach(item => {
          //  tr
          rows.push(item as TableItem);
        });
      });
      rows.forEach((row, rowIndex) => {
        const tableRow = dequeueRow(rowIndex, row as TableItem);
        row.children.forEach((cell, cellIndex) => {
          dequeueCell(tableRow, cellIndex, cell as TableItem);
        });
        if (tableRow.cells.length > row.children.length) {
          tableRow.cells.splice(row.children.length);
        }
      });
      if (this.table.rows.length > rows.length) {
        this.table.rows.splice(rows.length);
      }
    }
  }
  aboutToAppear(): void {
    this.styledEmbed.embedController.updateEmbed = embed => {
      this.styledEmbed = embed;
    };
    this.styledEmbed.embedController.currentArea = () => {
      return this.currentArea;
    };
    this.barOption = this.sharedEngine.event!.invokeTableBarOption({ bridge: this.bridge });
    this.reload();
  }

  build() {
    Column() {
      Row()
        .width('100%')
        .height(20)
      ContentBoxComponent({
        content: () => { this.TableContent() },
        bar: {
          title: this.barOption?.title ?? '表格',
          actions: this.barOption?.actions ?? [
            // ContentBoxBar.copyAction(undefined, this.sharedEngine),
            ContentBoxBar.openAction(undefined, this.sharedEngine),
          ],
        },
        onActionClick: (action, event) => {
          this.sharedEngine.event!.invokeTableActionClick({
            bridge: this.bridge,
            action, event,
          });
        },
      })
        .width('100%')
    }
      .position(this.styledEmbed?.position)
      .onAreaChange((oldValue, newValue) => {
        this.currentArea = MDArea.area(newValue);
        if (!MDArea.mdAreaEqual(MDArea.area(oldValue), MDArea.area(newValue))) {
          this.styledEmbed?.componentAreaChange(oldValue, newValue);
        }
        this.table.onAreaChange(oldValue, newValue);
      })
      .visibility(this.table.ready ? Visibility.Visible : Visibility.Hidden)
      .width(this.styledEmbed?.initMetrics.width)
  }

  @Builder
  TableContent() {
    List() {
      ForEach(this.table.rows, (row: DSTableRow) => {
        if (row.parent?.itemType === ETableItem.Head) {
          //  Table TH
          ListItem() {
            this.TableRow({ row, styles: [new StyledTextValue(this.theme.table?.headerFont)] })
          }
          .backgroundColor(this.theme.table?.headerBackgroundColor)
        } else {
          //  Table TD
          ListItem() {
            this.TableRow({ row, styles: [new StyledTextValue(this.theme.table?.contentFont)] })
          }
        }
      }, (row: DSTableRow) => row.likelyKey)
    }
  }
  // 单元格内容绝大多数是几个字的纯样式文本：直接构建 StyledString 交给
  // TextComponent 渲染（与 EmbedComponent 内部同一渲染方式），省掉每格一个
  // EmbedComponent + Stack 的组件开销；含嵌入（图片等）的单元格回落旧路径。
  // 缓存按 node 实例身份失效，reload 换 node 后会重建。
  private ensureCellStyled(cell: DSTableCell, styles?: StyledValue[]): StyledObject {
    const node = cell.node?.deref();
    if (cell.styledCache !== undefined && cell.styledCacheNode === node) {
      return cell.styledCache;
    }
    let hasEmbed = false;
    const content = StyledObject.root({ width: this.theme.table?.cellMaxWidth }, styles)
      .on<IStyledObjectAppendEvent>(EStyledObjectEvent.DidAppend, event => {
        if (event.target.type === EStyledObject.Embed) {
          hasEmbed = true;
        }
      });
    if (node) {
      Styled.create({ node })?.build({
        theme: this.theme,
        engine: this.sharedEngine,
        didCreateStyled: (styled) => {
          content.attach(styled);
        },
      });
    }
    cell.styledCache = content;
    cell.styledCacheNode = node;
    cell.styledHasEmbed = hasEmbed;
    return content;
  }
  private cellNeedsEmbed(cell: DSTableCell, styles?: StyledValue[]): boolean {
    this.ensureCellStyled(cell, styles);
    return cell.styledHasEmbed;
  }

  @Builder
  TableRow(data: ITableRowData) {
    Row() {
      ForEach(data.row.cells, (cell: DSTableCell) => {
        Row() {
          Scroll() {
            if (this.cellNeedsEmbed(cell, data.styles)) {
              EmbedComponent({
                node: cell.node?.deref(),
                area: { width: this.theme.table?.cellMaxWidth },
                styles: data.styles,
              })
                .constraintSize(cell.constraintSize(this.styledEmbed.blockArea, this.theme))
                .onAreaChange((oldValue, newValue) => {
                  if (MDArea.mdAreaEqual(MDArea.area(oldValue), MDArea.area(newValue))) {
                    return;
                  }
                  cell.table?.deref()?.cellAreaChange(cell, oldValue, newValue);
                })
            } else {
              TextComponent({
                content: this.ensureCellStyled(cell, data.styles),
              })
                .constraintSize(cell.constraintSize(this.styledEmbed.blockArea, this.theme))
                .onAreaChange((oldValue, newValue) => {
                  if (MDArea.mdAreaEqual(MDArea.area(oldValue), MDArea.area(newValue))) {
                    return;
                  }
                  cell.table?.deref()?.cellAreaChange(cell, oldValue, newValue);
                })
            }
          }
          .align(Alignment.TopStart)
          .scrollable(ScrollDirection.None)
          .constraintSize({ minWidth: cell.width, minHeight: cell.height })
        }
        .padding(this.theme.contentBox?.barMargin ? MDMargin.lengthMargin(this.theme.contentBox?.barMargin) : undefined)
        .borderWidth(cell.borderWidth(this.theme))
        .borderColor(this.theme.contentBox?.border?.color)
      }, (cell: DSTableCell) => cell.likelyKey)
    }
  }
}
interface ITableRowData {
  row: DSTableRow;
  styles?: StyledValue[];
}

/**
 * DataSource for Table
 */

@ObservedV2
class DSTable {
  private static gid: number = 0;
  private static createGID() {
    return DSTable.gid++;
  }
  readonly ID: number = DSTable.createGID();

  @Trace rows: DSTableRow[] = [];
  @Trace ready: boolean = false;

  cellAreaChange(cell: DSTableCell, _oldValue: Area, newValue: Area) {
    //  re-layout row
    do {
      let maxHeight: Length = newValue.height;
      const cells: DSTableCell[] = cell.row.deref()?.cells ?? [];
      cells.forEach(ele => {
        if (ele.height !== undefined && ele.height > maxHeight) {
          maxHeight = ele.height;
        }
      });
      cells.forEach(ele => {
        if (ele.height !== undefined && ele.height !== maxHeight) {
          ele.height = maxHeight;
        }
      });
      if (cell.height === undefined) {
        cell.height = maxHeight;
      }
    } while (0);
    //  re-layout column
    do {
      let maxWidth: Length = newValue.width;
      const index = cell.index;
      if (index !== undefined) {
        this.rows.forEach(row => {
          if (row.cells.length > index) {
            const column = row.cells[index];
            if (column.width !== undefined && column.width > maxWidth) {
              maxWidth = column.width;
            }
          }
        });
        this.rows.forEach(row => {
          if (row.cells.length > index) {
            const column = row.cells[index];
            if (column.width !== undefined && column.width !== maxWidth) {
              column.width = maxWidth;
            }
          }
        });
        if (cell.width === undefined) {
          cell.width = maxWidth;
        }
      }
    } while (0);
  }
  onAreaChange(_oldValue: Area, _newValue: Area) {
    if (this.ready) {
      return;
    }
    let allCellReady: boolean = true;
    this.rows.forEach(row => {
      row.cells.forEach(cell => {
        if (cell.width === undefined || cell.height === undefined) {
          allCellReady = false;
        }
      });
    });
    if (allCellReady) {
      this.ready = true;
    }
  }
}

@ObservedV2
class DSTableRow {
  private static gid: number = 0;
  private static createGID() {
    return DSTableRow.gid++;
  }
  readonly ID: number = DSTableRow.createGID();

  @Trace cells: DSTableCell[] = [];
  table?: WeakRef<DSTable>;
  node?: WeakRef<TableItem>;
  constructor(node?: TableItem, table?: DSTable) {
    if (node) {
      this.node = new WeakRef(node);
    }
    if (table) {
      this.table = new WeakRef(table);
    }
  }
  get index(): number | undefined {
    return this.table?.deref()?.rows.indexOf(this);
  }
  get parent(): TableItem | undefined {
    const parent = this.node?.deref()?.parent?.deref();
    if (parent?.is(ENode.TableItem)) {
      return parent as TableItem;
    }
    return undefined;
  }
  get likelyKey(): string | undefined {
    return `row:${this.index}`;
  }
}
type DSTableCellRef = string;
@ObservedV2
class DSTableCell {
  private static gid: number = 0;
  private static createGID() {
    return DSTableCell.gid++;
  }
  readonly ID: number = DSTableCell.createGID();

  @Trace node?: WeakRef<TableItem>;
  table?: WeakRef<DSTable>;
  row: WeakRef<DSTableRow>;

  @Trace width?: Length;
  @Trace height?: Length;

  // 单元格 StyledString 缓存（轻量渲染路径用），按 node 实例身份失效。
  styledCache?: StyledObject;
  styledCacheNode?: TableItem;
  styledHasEmbed: boolean = false;

  constructor(row: DSTableRow, node?: TableItem, table?: DSTable) {
    this.row = new WeakRef(row);
    if (node) {
      this.node = new WeakRef(node);
    }
    if (table) {
      this.table = new WeakRef(table);
    }
  }
  isEmpty() {
    return !this.node;
  }
  constraintSize(area?: IMDArea, theme?: ITheme): ConstraintSizeOptions {
    const length = this.row.deref()?.cells.length ?? 0;
    const marginWidth = MDLength.vp(
      (theme?.contentBox?.barMargin?.left?.value ?? 0) +
        (theme?.contentBox?.barMargin?.right?.value ?? 0)
    )
    const borderWidth = MDLength.vp(theme?.contentBox?.border?.width?.value ?? 0);
    //  border_count = cell_left ( length - 1 ) + table_left_right ( 1 + 1 ) = length + 1
    let width = MDLength.vp((area?.width?.value ?? 0) - marginWidth.value * length - borderWidth.value * (length + 1));
    let minWidth: LengthMetrics = MDLength.vp(width.value / (length || 1));
    let maxWidth: LengthMetrics = this.index === 0 ?
      theme?.table?.cellMaxWidth4First ?? MDLength.vp(0) :
      theme?.table?.cellMaxWidth ?? MDLength.vp(0);
    maxWidth = MDLength.vp(maxWidth.value - marginWidth.value - borderWidth.value);
    if (maxWidth.value < minWidth.value) {
      maxWidth = minWidth;
    }
    if (length === 1) {
      return {
        minWidth: minWidth.value > 0 ? MDLength.metrics2length(minWidth) : undefined,
      };
    } else {
      return {
        maxWidth: maxWidth.value > 0 ? MDLength.metrics2length(maxWidth) : undefined,
        minWidth: minWidth.value > 0 ? MDLength.metrics2length(minWidth) : undefined,
      };
    }
  }
  borderWidth(theme?: ITheme): EdgeWidths {
    const width = MDLength.metrics2length(
      theme?.contentBox?.border?.width ??
      MDLength.vp(0)
    );
    return {
      top: width,
      left: this.index !== 0 ? width : undefined,
    };
  }
  get index(): number | undefined {
    return this.row.deref()?.cells.indexOf(this);
  }
  get ref(): DSTableCellRef {
    return `${this.row.deref()?.index ?? -1}:${this.index ?? -1}`;
  }
  get likelyKey(): string | undefined {
    return `row:${this.row?.deref()?.index}_cell:${this.index}`;
  }
}

/**
 * Event
 */

interface ITableComponentBridge {
  styledEmbed: () => StyledEmbed,
}
export class TableComponentBridge {
  private option: ITableComponentBridge;
  constructor(option: ITableComponentBridge) {
    this.option = option;
  }
  get styledEmbed() {
    return this.option.styledEmbed();
  }
}
export interface ITableComponentEvent {
  bridge: TableComponentBridge;
}
export interface ITableComponentActionClickEvent extends ITableComponentEvent {
  action: IContentBoxAction,
  event: ClickEvent,
}
