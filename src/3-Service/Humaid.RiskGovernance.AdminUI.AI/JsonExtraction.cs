namespace Humaid.RiskGovernance.AdminUI.AI
{
    using System.Text;
    using System.Text.Json;

    internal static class JsonExtraction
    {
        public static readonly JsonSerializerOptions CaseInsensitive = new() { PropertyNameCaseInsensitive = true };

        /// <summary>Strips a ```json ... ``` (or bare ```...```) fence if Claude wrapped its JSON
        /// output in one despite the prompt asking it not to.</summary>
        public static string ExtractJson(string text)
        {
            var trimmed = text.Trim();
            if (trimmed.StartsWith("```"))
            {
                var firstNewline = trimmed.IndexOf('\n');
                var lastFence = trimmed.LastIndexOf("```", StringComparison.Ordinal);
                if (firstNewline >= 0 && lastFence > firstNewline)
                    trimmed = trimmed[(firstNewline + 1)..lastFence].Trim();
            }

            // Some models add prose before or after the JSON; keep only the outermost object/array.
            var start = trimmed.IndexOfAny(['{', '[']);
            if (start < 0) return trimmed;
            var end = trimmed.LastIndexOf(trimmed[start] == '{' ? '}' : ']');
            return EscapeControlCharsInStrings(end > start ? trimmed[start..(end + 1)] : trimmed);
        }

        /// <summary>Multi-paragraph output (the narrative) sometimes comes back with literal line
        /// breaks inside a JSON string instead of \n, which System.Text.Json rightly rejects
        /// ("'0x0A' is invalid within a JSON string" - seen in dev on CR-2026-00109). Escapes raw
        /// control characters inside string literals only; whitespace between tokens is left alone.</summary>
        private static string EscapeControlCharsInStrings(string json)
        {
            StringBuilder? sb = null;
            var inString = false;
            var escaped = false;

            for (var i = 0; i < json.Length; i++)
            {
                var c = json[i];
                string? replacement = null;

                if (escaped)
                {
                    escaped = false;
                }
                else if (c == '\\' && inString)
                {
                    escaped = true;
                }
                else if (c == '"')
                {
                    inString = !inString;
                }
                else if (inString && c < ' ')
                {
                    replacement = c switch
                    {
                        '\n' => "\\n",
                        '\r' => "\\r",
                        '\t' => "\\t",
                        _ => $"\\u{(int)c:x4}",
                    };
                }

                if (replacement is not null)
                {
                    sb ??= new StringBuilder(json, 0, i, json.Length + 16);
                    sb.Append(replacement);
                }
                else
                {
                    sb?.Append(c);
                }
            }

            return sb?.ToString() ?? json;
        }
    }
}
