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
            Console.WriteLine("FAIL: 대상 파일 경로가 누락되었습니다.");
            return 1;
        }

        string filePath = args[0];
        if (!File.Exists(filePath))
        {
            Console.WriteLine(string.Format("FAIL: 파일이 존재하지 않습니다: {0}", filePath));
            return 1;
        }

        string text = File.ReadAllText(filePath, Encoding.UTF8);
        int fatalCount = 0;
        int warnCount = 0;

        Console.WriteLine(string.Format("=== [SRS DETERMINISTIC LINTER] 분석 대상: {0} ===", Path.GetFileName(filePath)));

        // 1. 공백 없는 물결표 검사 (~ 범위 표기 금기)
        var tildeMatches = Regex.Matches(text, @"\d+~\d+");
        foreach (Match m in tildeMatches)
        {
            Console.WriteLine(string.Format("[FATAL] 공백 없는 물결표 금기 위반: '{0}' (올바른 형식: ' ~ ')", m.Value));
            fatalCount++;
        }

        // 2. 미확정 TBD / TODO 방치 검사
        var todoMatches = Regex.Matches(text, @"(?i)\b(TODO|TBD|FIXME|미정|추후 결정)\b");
        foreach (Match m in todoMatches)
        {
            Console.WriteLine(string.Format("[WARNING] 미확정 항목 잔류: '{0}' at index {1}", m.Value, m.Index));
            warnCount++;
        }

        // 3. 요구사항 ID 형식 점검 (예: REQ-, SRS-, SEC-, PERF-)
        bool hasReqId = Regex.IsMatch(text, @"\b(REQ|SRS|UC|API|SEC|PERF)-[A-Z0-9_-]+");
        if (!hasReqId)
        {
            Console.WriteLine("[WARNING] 표준 요구사항 식별자(REQ-, SRS-, UC- 등)가 발견되지 않았습니다.");
            warnCount++;
        }

        // 4. 모호한 표현 검사 (소프트웨어 공학 금기어: 적절히, 알아서, 빠르고 안정적으로, 거의)
        var ambiguousWords = new string[] { "적절히", "적당히", "알아서", "빠르고 안정적인", "최대한 빠르게", "문제없이 잘" };
        foreach (var word in ambiguousWords)
        {
            if (text.Contains(word))
            {
                Console.WriteLine(string.Format("[WARNING] 비결정론적/모호한 요구사항 표현 감지: '{0}'", word));
                warnCount++;
            }
        }

        Console.WriteLine(string.Format("=== 검증 결과: FATAL={0}, WARNING={1} ===", fatalCount, warnCount));
        if (fatalCount > 0)
        {
            Console.WriteLine(">>> [FAIL] 하드게이트 위반으로 거부되었습니다.");
            return 2;
        }

        Console.WriteLine(">>> [PASS] 모든 필수 무결성 검증을 통과했습니다.");
        return 0;
    }
}
