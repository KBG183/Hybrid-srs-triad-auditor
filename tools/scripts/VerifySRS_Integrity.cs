using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace SrsIntegrity.Engine
{
    /// <summary>
    /// 高信頼性エンタープライズ要件定義書（SRS）テキスト整合性およびヒューマンエラー遮断リンター
    /// (High-Reliability Enterprise SRS Text Integrity & Human-Error Blocker)
    /// </summary>
    public class SrsIntegrityVerifier
    {
        public class Finding
        {
            public string RuleId { get; set; }
            public string Severity { get; set; } // FATAL, WARN, INFO
            public int LineNumber { get; set; }
            public int ColumnNumber { get; set; }
            public string Message { get; set; }
            public string ContextSnippet { get; set; }
        }

        public class VerificationResult
        {
            public int ExitCode { get; set; }
            public int FatalCount { get; set; }
            public int WarningCount { get; set; }
            public List<Finding> Findings { get; set; }

            public VerificationResult()
            {
                Findings = new List<Finding>();
            }
        }

        public static int Main(string[] args)
        {
            if (args.Length == 0)
            {
                Console.WriteLine("Usage: VerifySRS_Integrity.exe <TargetFilePath> [PolicyRulesPath]");
                return 3;
            }

            string targetFile = args[0];
            string policyFile = args.Length > 1 ? args[1] : null;

            VerificationResult result = Verify(targetFile, policyFile);
            return result.ExitCode;
        }

        public static VerificationResult Verify(string filePath, string policyPath = null)
        {
            VerificationResult result = new VerificationResult();

            if (!File.Exists(filePath))
            {
                Console.WriteLine(string.Format("[EXECUTION ERROR] Target file not found: {0}", filePath));
                result.ExitCode = 3;
                return result;
            }

            byte[] rawBytes;
            try
            {
                rawBytes = File.ReadAllBytes(filePath);
            }
            catch (Exception ex)
            {
                Console.WriteLine(string.Format("[EXECUTION ERROR] Failed to read bytes: {0}", ex.Message));
                result.ExitCode = 3;
                return result;
            }

            // =========================================================================
            // PHASE 1: Byte-Level & Encoding Integrity (Fail-Closed)
            // =========================================================================
            
            // 1-1. BOM Check (Rule: TEXT-001)
            if (rawBytes.Length >= 3 && rawBytes[0] == 0xEF && rawBytes[1] == 0xBB && rawBytes[2] == 0xBF)
            {
                result.Findings.Add(new Finding
                {
                    RuleId = "TEXT-001",
                    Severity = "WARN",
                    LineNumber = 1,
                    ColumnNumber = 1,
                    Message = "UTF-8 BOM detected. Enterprise git repos standardly require UTF-8 without BOM.",
                    ContextSnippet = "BOM [EF BB BF]"
                });
            }

            // 1-2. Split into raw lines using LF/CRLF while preserving line indices
            List<byte[]> rawLines = SplitBytesIntoLines(rawBytes);

            for (int i = 0; i < rawLines.Count; i++)
            {
                int lineNum = i + 1;
                byte[] lBytes = rawLines[i];

                // Carriage Return check (TEXT-005)
                for (int b = 0; b < lBytes.Length; b++)
                {
                    if (lBytes[b] == 0x0D)
                    {
                        result.Findings.Add(new Finding
                        {
                            RuleId = "TEXT-005",
                            Severity = "WARN",
                            LineNumber = lineNum,
                            ColumnNumber = b + 1,
                            Message = "Carriage Return (CR, 0x0D) detected. Unified LF line-ending is recommended.",
                            ContextSnippet = "\\r detected"
                        });
                        break;
                    }
                }

                // Invisible Characters (Zero-Width Space, Soft Hyphen, etc.)
                // U+200B (Zero-width space: E2 80 8B)
                // U+FEFF in-body (Zero-width no-break space: EF BB BF)
                // U+00AD (Soft hyphen: C2 AD)
                for (int b = 0; b < lBytes.Length; b++)
                {
                    if (b + 2 < lBytes.Length && lBytes[b] == 0xE2 && lBytes[b + 1] == 0x80 && lBytes[b + 2] == 0x8B)
                    {
                        result.Findings.Add(new Finding
                        {
                            RuleId = "TEXT-002",
                            Severity = "FATAL",
                            LineNumber = lineNum,
                            ColumnNumber = b + 1,
                            Message = "Zero-Width Space (U+200B) detected. Hidden non-printable characters violate strict spec integrity.",
                            ContextSnippet = "[E2 80 8B]"
                        });
                    }
                    if (b + 2 < lBytes.Length && lBytes[b] == 0xEF && lBytes[b + 1] == 0xBB && lBytes[b + 2] == 0xBF && lineNum > 1)
                    {
                        result.Findings.Add(new Finding
                        {
                            RuleId = "TEXT-001",
                            Severity = "FATAL",
                            LineNumber = lineNum,
                            ColumnNumber = b + 1,
                            Message = "U+FEFF (Zero-Width No-Break Space) detected within body.",
                            ContextSnippet = "[EF BB BF]"
                        });
                    }
                    if (b + 1 < lBytes.Length && lBytes[b] == 0xC2 && lBytes[b + 1] == 0xAD)
                    {
                        result.Findings.Add(new Finding
                        {
                            RuleId = "TEXT-003",
                            Severity = "FATAL",
                            LineNumber = lineNum,
                            ColumnNumber = b + 1,
                            Message = "Soft Hyphen (U+00AD) detected. Invisible hyphenation breaks automated parser contracts.",
                            ContextSnippet = "[C2 AD]"
                        });
                    }
                    // U+FFFD (Replacement character: EF BF BD) - Corrupted UTF-8
                    if (b + 2 < lBytes.Length && lBytes[b] == 0xEF && lBytes[b + 1] == 0xBF && lBytes[b + 2] == 0xBD)
                    {
                        result.Findings.Add(new Finding
                        {
                            RuleId = "TEXT-004",
                            Severity = "FATAL",
                            LineNumber = lineNum,
                            ColumnNumber = b + 1,
                            Message = "Corrupted UTF-8 Replacement Character (U+FFFD) detected.",
                            ContextSnippet = "[EF BF BD]"
                        });
                    }
                }
            }

            // =========================================================================
            // PHASE 2: Spec Syntax & Quality Rules (Line-by-Line)
            // =========================================================================
            // Strict UTF-8 decoder that throws DecoderFallbackException on any invalid byte sequence
            UTF8Encoding strictUtf8 = new UTF8Encoding(false, true);
            string fullText;
            try
            {
                fullText = strictUtf8.GetString(rawBytes);
            }
            catch (DecoderFallbackException ex)
            {
                Console.WriteLine(string.Format("[FATAL] [TEXT-004] Invalid non-UTF-8 byte sequence detected: {0}", ex.Message));
                result.Findings.Add(new Finding
                {
                    RuleId = "TEXT-004",
                    Severity = "FATAL",
                    LineNumber = 1,
                    ColumnNumber = 1,
                    Message = "Invalid non-UTF-8 byte sequence detected (Encoding integrity violated).",
                    ContextSnippet = ex.Message
                });
                result.ExitCode = 2;
                return result;
            }
            catch (Exception ex)
            {
                Console.WriteLine(string.Format("[EXECUTION ERROR] UTF-8 decoding failed: {0}", ex.Message));
                result.ExitCode = 3;
                return result;
            }

            string[] lines = fullText.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);

            int consecutiveBlankLines = 0;
            Dictionary<string, int> headingTracker = new Dictionary<string, int>();

            for (int i = 0; i < lines.Length; i++)
            {
                int lineNum = i + 1;
                string line = lines[i];
                string trimmed = line.Trim();

                // 2-1. Excessive Consecutive Blank Lines (FORMAT-001)
                if (string.IsNullOrEmpty(trimmed))
                {
                    consecutiveBlankLines++;
                    if (consecutiveBlankLines >= 3)
                    {
                        result.Findings.Add(new Finding
                        {
                            RuleId = "FORMAT-001",
                            Severity = "WARN",
                            LineNumber = lineNum,
                            ColumnNumber = 1,
                            Message = string.Format("Excessive blank lines detected ({0} consecutive empty lines). Clean formatting required.", consecutiveBlankLines),
                            ContextSnippet = "(Empty line)"
                        });
                    }
                }
                else
                {
                    consecutiveBlankLines = 0;
                }

                // 2-2. Unspaced Tilde Violation (SPEC-001)
                // e.g. 10~20, 22:00~05:00 -> Causes markdown strikethrough corruption
                Match unspacedTilde = Regex.Match(line, @"([^\s`])~([^\s`])");
                if (unspacedTilde.Success && !line.Contains("```"))
                {
                    result.Findings.Add(new Finding
                    {
                        RuleId = "SPEC-001",
                        Severity = "FATAL",
                        LineNumber = lineNum,
                        ColumnNumber = unspacedTilde.Index + 1,
                        Message = string.Format("Unspaced tilde detected: '{0}'. Must use space-padded ' ~ ' or escape '\\~' to prevent markdown strikethrough.", unspacedTilde.Value),
                        ContextSnippet = GetContextSnippet(line, unspacedTilde.Index, 15)
                    });
                }

                // 2-3. Ambiguous Engineering Placeholders (SPEC-002)
                // e.g. TBD, TODO, 未定, 未確定, 追って決定
                Match placeholder = Regex.Match(line, @"\b(TBD|TODO|FIXME|WIP)\b|(未定|未確定|追って決定)");
                if (placeholder.Success && !line.Contains("chk_") && !line.Contains("SPEC-002") && !line.Contains("RULE-FMT-02"))
                {
                    result.Findings.Add(new Finding
                    {
                        RuleId = "SPEC-002",
                        Severity = "WARN",
                        LineNumber = lineNum,
                        ColumnNumber = placeholder.Index + 1,
                        Message = string.Format("Unfinalized specification placeholder detected: '{0}'. All requirements must be concrete in approved SSOT.", placeholder.Value),
                        ContextSnippet = GetContextSnippet(line, placeholder.Index, 15)
                    });
                }

                // 2-4. Duplicate Headings Check (SPEC-003)
                if (trimmed.StartsWith("#"))
                {
                    Match headingMatch = Regex.Match(trimmed, @"^(#+)\s+(.+)$");
                    if (headingMatch.Success)
                    {
                        string headingText = headingMatch.Groups[2].Value.Trim();
                        if (headingTracker.ContainsKey(headingText))
                        {
                            result.Findings.Add(new Finding
                            {
                                RuleId = "SPEC-003",
                                Severity = "WARN",
                                LineNumber = lineNum,
                                ColumnNumber = 1,
                                Message = string.Format("Duplicate heading detected: '{0}' (First seen at line {1}). Causes anchor conflicts.", headingText, headingTracker[headingText]),
                                ContextSnippet = trimmed
                            });
                        }
                        else
                        {
                            headingTracker[headingText] = lineNum;
                        }
                    }
                }
            }

            // =========================================================================
            // PHASE 3: Large Block Duplicate Detection (Anti-Copy-Paste Integrity)
            // =========================================================================
            Dictionary<string, int> paragraphSeen = new Dictionary<string, int>();
            StringBuilder currentBlock = new StringBuilder();
            int blockStartLine = 1;

            for (int i = 0; i < lines.Length; i++)
            {
                string line = lines[i];
                if (string.IsNullOrWhiteSpace(line))
                {
                    if (currentBlock.Length > 0)
                    {
                        CheckBlockDuplicate(currentBlock.ToString(), blockStartLine, paragraphSeen, result);
                        currentBlock.Clear();
                    }
                    blockStartLine = i + 2;
                }
                else
                {
                    currentBlock.AppendLine(line);
                }
            }
            if (currentBlock.Length > 0)
            {
                CheckBlockDuplicate(currentBlock.ToString(), blockStartLine, paragraphSeen, result);
            }

            // =========================================================================
            // Evaluation & Console Output
            // =========================================================================
            int fatalCount = 0;
            int warnCount = 0;

            Console.WriteLine(string.Format("=== [SRS Integrity Verifier v2.0] Analyzing: {0} ===", Path.GetFileName(filePath)));
            Console.WriteLine(string.Format("Total Lines: {0} | Total Bytes: {1}", lines.Length, rawBytes.Length));

            foreach (var f in result.Findings)
            {
                if (f.Severity == "FATAL") fatalCount++;
                if (f.Severity == "WARN") warnCount++;

                Console.WriteLine(string.Format("[{0}] [{1}] Line {2}, Col {3}: {4}",
                    f.Severity, f.RuleId, f.LineNumber, f.ColumnNumber, f.Message));
                if (!string.IsNullOrEmpty(f.ContextSnippet))
                {
                    Console.WriteLine(string.Format("   Evidence: {0}", f.ContextSnippet));
                }
            }

            result.FatalCount = fatalCount;
            result.WarningCount = warnCount;

            if (fatalCount > 0)
            {
                Console.WriteLine(string.Format(">>> VERDICT: FAIL (FATAL Violations: {0}, Warnings: {1})", fatalCount, warnCount));
                result.ExitCode = 1;
            }
            else if (warnCount > 0)
            {
                Console.WriteLine(string.Format(">>> VERDICT: PASS WITH WARNINGS (Warnings: {0})", warnCount));
                result.ExitCode = 0;
            }
            else
            {
                Console.WriteLine(">>> VERDICT: PASS (Clean Integrity, Zero Defects)");
                result.ExitCode = 0;
            }

            return result;
        }

        private static void CheckBlockDuplicate(string blockText, int lineNum, Dictionary<string, int> seen, VerificationResult result)
        {
            // Normalize spaces
            string clean = Regex.Replace(blockText, @"\s+", " ").Trim();
            if (clean.Length < 100) return; // Skip small blocks

            // Ignore markdown tables and code blocks for duplicate checks
            if (clean.StartsWith("|") || clean.StartsWith("```")) return;

            if (seen.ContainsKey(clean))
            {
                result.Findings.Add(new Finding
                {
                    RuleId = "INTEGRITY-DUP-001",
                    Severity = "WARN",
                    LineNumber = lineNum,
                    ColumnNumber = 1,
                    Message = string.Format("Identical text block (>100 chars) detected. Previously seen at line {0}.", seen[clean]),
                    ContextSnippet = clean.Substring(0, Math.Min(60, clean.Length)) + "..."
                });
            }
            else
            {
                seen[clean] = lineNum;
            }
        }

        private static List<byte[]> SplitBytesIntoLines(byte[] bytes)
        {
            List<byte[]> lines = new List<byte[]>();
            int start = 0;
            for (int i = 0; i < bytes.Length; i++)
            {
                if (bytes[i] == 0x0A) // LF
                {
                    int len = i - start;
                    byte[] line = new byte[len];
                    Array.Copy(bytes, start, line, 0, len);
                    lines.Add(line);
                    start = i + 1;
                }
            }
            if (start < bytes.Length)
            {
                int len = bytes.Length - start;
                byte[] line = new byte[len];
                Array.Copy(bytes, start, line, 0, len);
                lines.Add(line);
            }
            return lines;
        }

        private static string GetContextSnippet(string line, int colIndex, int range)
        {
            if (string.IsNullOrEmpty(line)) return "";
            int start = Math.Max(0, colIndex - range);
            int len = Math.Min(line.Length - start, (range * 2) + 1);
            return line.Substring(start, len).Trim();
        }
    }
}
