using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;

/// <summary>
/// KINTAI Enterprise SRS Deterministic Linter v1.1
/// Pragmatic 2-Tier Architecture: Fail-Closed Hard-Gate for Structure, IDOR Security, and Syntax
/// </summary>
public class VerifySRS
{
    public static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        if (args.Length == 0)
        {
            Console.WriteLine("[FATAL] Target file path argument is missing.");
            return 1;
        }

        string filePath = args[0];
        if (!File.Exists(filePath))
        {
            Console.WriteLine(string.Format("[FATAL] File does not exist: {0}", filePath));
            return 1;
        }

        string text = File.ReadAllText(filePath, Encoding.UTF8);
        int fatalCount = 0;
        int warnCount = 0;

        Console.WriteLine(string.Format("=== [SRS DETERMINISTIC LINTER v1.1] Target: {0} ===", Path.GetFileName(filePath)));

        // =========================================================================
        // 1. [RULE-FMT-01] Markdown Syntax & Strikethrough Protection (Unspaced Tilde)
        // =========================================================================
        var tildeMatches = Regex.Matches(text, @"([^\s`])~([^\s`])");
        foreach (Match m in tildeMatches)
        {
            // Ignore code blocks
            int idx = m.Index;
            string before = text.Substring(0, idx);
            int codeBlockCount = Regex.Matches(before, @"```").Count;
            if (codeBlockCount % 2 == 0)
            {
                Console.WriteLine(string.Format("[FATAL] [RULE-FMT-01] Unspaced tilde taboo violated: '{0}' (Required format: ' ~ ')", m.Value));
                fatalCount++;
            }
        }

        // =========================================================================
        // 2. [RULE-FMT-02] Unfinalized Placeholders (TODO, TBD, 未定)
        // =========================================================================
        var todoMatches = Regex.Matches(text, @"(?i)\b(TODO|TBD|FIXME)\b|(未定|未確定|追って決定)");
        foreach (Match m in todoMatches)
        {
            Console.WriteLine(string.Format("[WARNING] [RULE-FMT-02] Unfinalized placeholder detected: '{0}' at index {1}", m.Value, m.Index));
            warnCount++;
        }

        // =========================================================================
        // 3. [RULE-REQ-03] 5 Mandatory Sections Enforcement per Requirement Block
        // =========================================================================
        var reqMatches = Regex.Matches(text, @"(?m)^#{3,4}\s+\[(REQ-[A-Z0-9_-]+)\]");
        if (reqMatches.Count == 0)
        {
            Console.WriteLine("[WARNING] No standard requirement blocks ([REQ-...]) detected.");
            warnCount++;
        }

        var mandatorySections = new Dictionary<string, string>
        {
            { "入力", @"-\s*\*\*入力.*?\*\*:" },
            { "処理", @"-\s*\*\*処理\*\*:" },
            { "出力", @"-\s*\*\*出力\*\*:" },
            { "例外処理", @"-\s*\*\*例外処理\*\*:" },
            { "完了基準 (DoD)", @"-\s*\*\*完了基準\s*\(DoD\)\*\*:" }
        };

        for (int i = 0; i < reqMatches.Count; i++)
        {
            string reqId = reqMatches[i].Groups[1].Value;
            int startIdx = reqMatches[i].Index;
            int endIdx = (i + 1 < reqMatches.Count) ? reqMatches[i + 1].Index : text.Length;
            string reqBlock = text.Substring(startIdx, endIdx - startIdx);

            foreach (var kvp in mandatorySections)
            {
                if (!Regex.IsMatch(reqBlock, kvp.Value))
                {
                    Console.WriteLine(string.Format("[FATAL] [RULE-REQ-03] Requirement '{0}' is missing mandatory section: '**{1}**'", reqId, kvp.Key));
                    fatalCount++;
                }
            }

            // =====================================================================
            // 4. [RULE-SEC-04] IDOR Security Gate (No Raw Client-Supplied ID Parameters)
            // =====================================================================
            if (reqId.StartsWith("REQ-STORE-") || reqId.StartsWith("REQ-STAFF-") || reqId.StartsWith("REQ-MEMBER-"))
            {
                // Inspect the "入力" section specifically
                var inputMatch = Regex.Match(reqBlock, @"-\s*\*\*入力.*?\*\*:(.*?)(?=-\s*\*\*(処理|出力|例外処理|完了基準)\*\*:|$)", RegexOptions.Singleline);
                if (inputMatch.Success)
                {
                    string inputContent = inputMatch.Groups[1].Value;
                    // Check if raw parameter declares ownerId or memberId as client input (excluding explanatory notes)
                    string[] inputLines = inputContent.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
                    foreach (string rawLine in inputLines)
                    {
                        string line = rawLine.Trim();
                        if (string.IsNullOrEmpty(line)) continue;

                        var idMatch = Regex.Match(line, @"(?i)\b(owner_?id|member_?id)\b");
                        if (idMatch.Success)
                        {
                            bool isSafe = line.Contains("リクエストパラメータから一切受け取らず") ||
                                          line.Contains("SecurityContext") ||
                                          line.Contains("完全禁止") ||
                                          line.Contains("JWT") ||
                                          line.Contains("クライアント指定不可") ||
                                          line.Contains("セッションから取得");

                            bool isDangerous = line.Contains("受け取る") ||
                                               line.Contains("受け付ける") ||
                                               line.Contains("クライアント") ||
                                               line.Contains("パラメータ") ||
                                               line.Contains("リクエスト") ||
                                               line.Contains("入力") ||
                                               line.Contains("必須") ||
                                               line.Contains("任意");

                            if (!isSafe && isDangerous)
                            {
                                Console.WriteLine(string.Format("[FATAL] [RULE-SEC-04] Insecure Direct Object Reference (IDOR) risk in '{0}': Client-supplied parameter '{1}' detected in line: {2}", reqId, idMatch.Value, line));
                                fatalCount++;
                            }
                        }
                    }
                }
            }

            // =====================================================================
            // 5. [RULE-STATE-05] State Transition Mapping Check for Status Lifecycle
            // =====================================================================
            if (reqBlock.Contains("ステータス") || reqBlock.Contains("状態遷移") || reqBlock.Contains("status"))
            {
                if (!reqBlock.Contains("→") && !reqBlock.Contains("->"))
                {
                    Console.WriteLine(string.Format("[WARNING] [RULE-STATE-05] Lifecycle status mentioned in '{0}' but no formal state transition arrow ('→') defined.", reqId));
                    warnCount++;
                }
            }
        }

        // =========================================================================
        // Result Summary & Verdict
        // =========================================================================
        Console.WriteLine(string.Format("=== Linter Results: FATAL={0}, WARNING={1} (Checked {2} Requirements) ===", fatalCount, warnCount, reqMatches.Count));
        if (fatalCount > 0)
        {
            Console.WriteLine(">>> [FAIL] Rejected due to hard-gate violation (Fail-Closed).");
            return 2;
        }

        Console.WriteLine(">>> [PASS] All mandatory integrity and security checks passed cleanly.");
        return 0;
    }
}
