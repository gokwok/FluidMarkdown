const MIN_INCREMENTAL_CONTENT_LENGTH = 4096;
const TARGET_TAIL_LENGTH = 3072;
const MIN_STABLE_PREFIX_LENGTH = 2048;

function isReferenceDefinition(line: string): boolean {
  const text = line.trim();
  if (text.length < 4 || text.charAt(0) !== '[') {
    return false;
  }
  const closing = text.indexOf(']:');
  return closing > 1;
}

function containsReferenceDefinition(content: string): boolean {
  const lines = content.split('\n');
  for (let index = 0; index < lines.length; index += 1) {
    if (isReferenceDefinition(lines[index])) {
      return true;
    }
  }
  return false;
}

interface IncrementalFence {
  marker: string;
  length: number;
  indent: number;
  tail: string;
}

function markdownFence(line: string): IncrementalFence | undefined {
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
  const tail: string = line.substring(end);
  if (marker === '`' && tail.indexOf('`') >= 0) {
    return undefined;
  }
  return { marker, length: end - start, indent: start, tail };
}

function blockHasCrossBoundaryShape(lines: string[], start: number, end: number): boolean {
  for (let index = start; index < end; index += 1) {
    const line = lines[index];
    const text = line.trim();
    if (text.length === 0) {
      continue;
    }
    if (line.charAt(0) === ' ' || line.charAt(0) === '\t' || text.charAt(0) === '>') {
      return true;
    }
    if (/^([-+*]|\d+[.)])\s+/.test(text)) {
      return true;
    }
  }
  return false;
}

function nextBlockStartsWithCrossBoundaryShape(lines: string[], start: number): boolean {
  for (let index = start; index < lines.length; index += 1) {
    const line = lines[index];
    const text = line.trim();
    if (text.length === 0) {
      continue;
    }
    if (line.charAt(0) === ' ' || line.charAt(0) === '\t' || text.charAt(0) === '>') {
      return true;
    }
    return /^([-+*]|\d+[.)])\s+/.test(text);
  }
  return false;
}

export function findIncrementalMarkdownSplit(content: string): number {
  if (content.length < MIN_INCREMENTAL_CONTENT_LENGTH || containsReferenceDefinition(content)) {
    return -1;
  }
  const target: number = content.length - TARGET_TAIL_LENGTH;
  if (target < MIN_STABLE_PREFIX_LENGTH) {
    return -1;
  }
  const lines: string[] = content.split('\n');
  const starts: number[] = [];
  let offset: number = 0;
  for (let index = 0; index < lines.length; index += 1) {
    starts.push(offset);
    offset += lines[index].length + 1;
  }

  let activeFence: IncrementalFence | undefined = undefined;
  let blockStart: number = 0;
  let best: number = -1;
  for (let index = 0; index < lines.length; index += 1) {
    const fence: IncrementalFence | undefined = markdownFence(lines[index]);
    if (activeFence === undefined) {
      if (fence !== undefined) {
        activeFence = fence;
      }
    } else if (fence !== undefined && fence.marker === activeFence.marker &&
      fence.length >= activeFence.length && fence.tail.trim().length === 0) {
      activeFence = undefined;
    }
    if (activeFence !== undefined || lines[index].trim().length > 0) {
      continue;
    }
    const candidate: number = index + 1 < starts.length ? starts[index + 1] : content.length;
    if (candidate > target) {
      break;
    }
    if (candidate >= MIN_STABLE_PREFIX_LENGTH &&
      !blockHasCrossBoundaryShape(lines, blockStart, index) &&
      !nextBlockStartsWithCrossBoundaryShape(lines, index + 1)) {
      best = candidate;
    }
    blockStart = index + 1;
  }
  return best;
}
