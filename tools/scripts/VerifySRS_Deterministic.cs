using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;

public class VerifySRS
{
    public static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        if (args.Length == 0)
        {
            Console.WriteLine("FAIL: Target file path argument is missing.");
            return 1;
        }

        string filePath = args[0];
        if (!File.Exists(filePath))
        {
            Console.WriteLine(string.Format("FAIL: File does not exist: {0}", filePath));
            return 1;
        }

        string text = File.ReadAllText(filePath, Encoding.UTF8);
        int fatalCount = 0;
        int warnCount = 0;

        Console.WriteLine(string.Format("=== [SRS DETERMINISTIC LINTER] Target: {0} ===", Path.GetFileName(filePath)));

        // 1. Unspaced tilde prohibition (~ range notation without spaces causes markdown strikethrough)
        var tildeMatches = Regex.Matches(text, @"\d+~\d+");
        foreach (Match m in tildeMatches)
        {
            Console.WriteLine(string.Format("[FATAL] Unspaced tilde taboo violated: '{0}' (Required format: ' ~ ')", m.Value));
            fatalCount++;
        }

        // 2. Unfinalized placeholders (TBD / TODO / 未定)
        var todoMatches = Regex.Matches(text, @"(?i)\b(TODO|TBD|FIXME)\b|(\b未定\b|\b未確定\b|\b追って決定\b)");
        foreach (Match m in todoMatches)
        {
            Console.WriteLine(string.Format("[WARNING] Unfinalized specification placeholder detected: '{0}' at index {1}", m.Value, m.Index));
            warnCount++;
        }

        // 3. Requirement ID standard format check (e.g. REQ-, SRS-, SEC-, PERF-, UC-)
        bool hasReqId = Regex.IsMatch(text, @"\b(REQ|SRS|UC|API|SEC|PERF)-[A-Z0-9_-]+");
        if (!hasReqId)
        {
            Console.WriteLine("[WARNING] Standard requirement identifier prefix (REQ-, SRS-, UC-, etc.) not found.");
            warnCount++;
        }

        // 4. Ambiguous specification terminology check
        var ambiguousWords = new string[] { "適切に", "適宜", "よしなに", "迅速かつ安定", "できる限り早く", "問題なく" };
        foreach (var word in ambiguousWords)
        {
            if (text.Contains(word))
            {
                Console.WriteLine(string.Format("[WARNING] Non-deterministic/ambiguous specification term detected: '{0}'", word));
                warnCount++;
            }
        }

        Console.WriteLine(string.Format("=== Linter Results: FATAL={0}, WARNING={1} ===", fatalCount, warnCount));
        if (fatalCount > 0)
        {
            Console.WriteLine(">>> [FAIL] Rejected due to hard-gate violation.");
            return 2;
        }

        Console.WriteLine(">>> [PASS] All mandatory integrity checks passed.");
        return 0;
    }
}
