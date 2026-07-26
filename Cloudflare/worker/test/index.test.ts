import { describe, expect, it } from "vitest";
import {
  classifyDevice,
  formatShortCode,
  generateShortCode,
  normalizeShortCode,
  page,
  parseRecentStatsLimit,
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

describe("recent statistics limits", () => {
  it("defaults to 20 and accepts bounded positive limits", () => {
    expect(parseRecentStatsLimit(null)).toBe(20);
    expect(parseRecentStatsLimit("1")).toBe(1);
    expect(parseRecentStatsLimit("100")).toBe(100);
  });

  it("rejects malformed and excessive limits", () => {
    expect(parseRecentStatsLimit("0")).toBeNull();
    expect(parseRecentStatsLimit("20.5")).toBeNull();
    expect(parseRecentStatsLimit("101")).toBeNull();
  });
});

describe("privacy-preserving device classification", () => {
  it("reduces user agents to broad device categories", () => {
    expect(classifyDevice("Mozilla/5.0 (iPhone; CPU iPhone OS)", "?1"))
      .toBe("mobile");
    expect(classifyDevice("Mozilla/5.0 (iPad; CPU OS 18_0)"))
      .toBe("tablet");
    expect(classifyDevice("Mozilla/5.0 (Macintosh; Intel Mac OS X)"))
      .toBe("desktop");
  });
});

describe("public video page", () => {
  it("prioritizes the player and shows the medical signature without a heading", () => {
    const html = page(
      "Vídeo do laudo",
      "Aviso do laudo.",
      "123456",
      "Assinatura profissional",
    );

    expect(html).toContain('src="/media/123-456"');
    expect(html).not.toContain("<h1>Vídeo complementar</h1>");
    expect(html).not.toContain("<h1>Vídeo do laudo</h1>");
    expect(html).toContain("Assinatura profissional");
    expect(html).toContain("width:100%");
    expect(html).not.toContain("Estatísticas técnicas");
    expect(html).toContain('/analytics/123456/"+event');
  });

  it("escapes the signature supplied by configuration", () => {
    const html = page("Vídeo", "Aviso.", "123456", "<script>alert(1)</script>");

    expect(html).toContain("&lt;script&gt;alert(1)&lt;/script&gt;");
    expect(html).not.toContain("<script>alert(1)</script>");
  });
});
