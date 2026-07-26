import { describe, expect, it } from "vitest";
import {
  formatShortCode,
  generateShortCode,
  normalizeShortCode,
} from "../src/index";

describe("short codes", () => {
  it("formats and normalizes six digits", () => {
    expect(formatShortCode("123456")).toBe("123-456");
    expect(normalizeShortCode("123-456")).toBe("123456");
    expect(normalizeShortCode("123456")).toBe("123456");
  });

  it("rejects zero prefixes and malformed values", () => {
    expect(normalizeShortCode("023-456")).toBeNull();
    expect(normalizeShortCode("12345")).toBeNull();
    expect(normalizeShortCode("abc-def")).toBeNull();
  });

  it("always generates a six digit non-zero-prefixed code", () => {
    for (const value of [0, 1, 899999, 900000, 0xffffffff]) {
      expect(generateShortCode(value)).toMatch(/^[1-9][0-9]{5}$/);
    }
  });
});
