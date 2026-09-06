export interface ZipEntry {
  name: string;
  content: string;
}

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let index = 0; index < 256; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    table[index] = value >>> 0;
  }
  return table;
})();

export const crc32 = (bytes: Uint8Array): number => {
  let crc = 0xffffffff;
  for (let index = 0; index < bytes.length; index += 1) {
    const byte = bytes[index] ?? 0;
    crc = (CRC_TABLE[(crc ^ byte) & 0xff] ?? 0) ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
};

interface PreparedEntry {
  nameBytes: Uint8Array;
  dataBytes: Uint8Array;
  crc: number;
  offset: number;
}

const LOCAL_HEADER_SIZE = 30;
const CENTRAL_HEADER_SIZE = 46;
const END_RECORD_SIZE = 22;

const LOCAL_SIGNATURE = 0x04034b50;
const CENTRAL_SIGNATURE = 0x02014b50;
const END_SIGNATURE = 0x06054b50;

const VERSION_STORE = 20;
const METHOD_STORE = 0;
const FLAG_UTF8_NAME = 0x0800;

class ByteWriter {
  private readonly bytes: Uint8Array<ArrayBuffer>;
  private cursor = 0;

  constructor(size: number) {
    this.bytes = new Uint8Array(new ArrayBuffer(size));
  }

  u16(value: number) {
    this.bytes[this.cursor] = value & 0xff;
    this.bytes[this.cursor + 1] = (value >>> 8) & 0xff;
    this.cursor += 2;
  }

  u32(value: number) {
    this.bytes[this.cursor] = value & 0xff;
    this.bytes[this.cursor + 1] = (value >>> 8) & 0xff;
    this.bytes[this.cursor + 2] = (value >>> 16) & 0xff;
    this.bytes[this.cursor + 3] = (value >>> 24) & 0xff;
    this.cursor += 4;
  }

  raw(chunk: Uint8Array) {
    this.bytes.set(chunk, this.cursor);
    this.cursor += chunk.length;
  }

  done(): Uint8Array<ArrayBuffer> {
    return this.bytes;
  }
}

const dosTime = (date: Date) =>
  ((date.getHours() << 11) | (date.getMinutes() << 5) | (date.getSeconds() >>> 1)) & 0xffff;

const dosDate = (date: Date) =>
  (((date.getFullYear() - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate()) & 0xffff;

export const buildZip = (entries: ZipEntry[], stamp: Date = new Date()): Blob => {
  const encoder = new TextEncoder();
  const time = dosTime(stamp);
  const day = dosDate(stamp);

  const prepared: PreparedEntry[] = [];
  let offset = 0;

  for (const entry of entries) {
    const nameBytes = encoder.encode(entry.name);
    const dataBytes = encoder.encode(entry.content);
    prepared.push({ nameBytes, dataBytes, crc: crc32(dataBytes), offset });
    offset += LOCAL_HEADER_SIZE + nameBytes.length + dataBytes.length;
  }

  const localSize = offset;
  const centralSize = prepared.reduce(
    (total, item) => total + CENTRAL_HEADER_SIZE + item.nameBytes.length,
    0
  );

  const writer = new ByteWriter(localSize + centralSize + END_RECORD_SIZE);

  for (const item of prepared) {
    writer.u32(LOCAL_SIGNATURE);
    writer.u16(VERSION_STORE);
    writer.u16(FLAG_UTF8_NAME);
    writer.u16(METHOD_STORE);
    writer.u16(time);
    writer.u16(day);
    writer.u32(item.crc);
    writer.u32(item.dataBytes.length);
    writer.u32(item.dataBytes.length);
    writer.u16(item.nameBytes.length);
    writer.u16(0);
    writer.raw(item.nameBytes);
    writer.raw(item.dataBytes);
  }

  for (const item of prepared) {
    writer.u32(CENTRAL_SIGNATURE);
    writer.u16(VERSION_STORE);
    writer.u16(VERSION_STORE);
    writer.u16(FLAG_UTF8_NAME);
    writer.u16(METHOD_STORE);
    writer.u16(time);
    writer.u16(day);
    writer.u32(item.crc);
    writer.u32(item.dataBytes.length);
    writer.u32(item.dataBytes.length);
    writer.u16(item.nameBytes.length);
    writer.u16(0);
    writer.u16(0);
    writer.u16(0);
    writer.u16(0);
    writer.u32(0);
    writer.u32(item.offset);
    writer.raw(item.nameBytes);
  }

  writer.u32(END_SIGNATURE);
  writer.u16(0);
  writer.u16(0);
  writer.u16(prepared.length);
  writer.u16(prepared.length);
  writer.u32(centralSize);
  writer.u32(localSize);
  writer.u16(0);

  return new Blob([writer.done()], { type: "application/zip" });
};

export const saveBlob = (blob: Blob, fileName: string) => {
  const href = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = href;
  anchor.download = fileName;
  anchor.rel = "noopener";
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(href), 1000);
};
