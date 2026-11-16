/**
 * 设计令牌：与 prototypes/ 下的高保真原型逐像素对齐。
 * 颜色取自原型实测值，数值不要随意改动，改动会与原型不一致。
 */
export class Color {
  static readonly bg: string = '#F5F1EA';
  static readonly card: string = '#FFFFFF';
  static readonly ink: string = '#1E2420';
  static readonly ink2: string = '#454B47';
  static readonly muted: string = '#8C8A82';
  static readonly muted2: string = '#B4B0A5';
  static readonly green: string = '#2C5F55';
  static readonly greenDeep: string = '#1F4039';
  static readonly greenSoft: string = '#E6F0EC';
  static readonly line: string = '#E8E2D6';
  static readonly warmBg: string = '#FDF6E8';
  static readonly warmLine: string = '#EAD9B4';
  static readonly warmInk: string = '#A8742A';
  static readonly dash: string = '#DCD5C4';
}

export class Size {
  /** 页面左右安全边距 */
  static readonly pageH: number = 24;
  static readonly radiusCard: number = 16;
  static readonly radiusSheet: number = 24;
  static readonly navBar: number = 52;
}

export class Font {
  static readonly display: number = 28;
  static readonly title: number = 26;
  static readonly section: number = 17;
  static readonly body: number = 15;
  static readonly caption: number = 13;
  static readonly tiny: number = 11.5;
}
