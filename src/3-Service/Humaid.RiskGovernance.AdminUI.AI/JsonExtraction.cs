namespace Humaid.RiskGovernance.AdminUI.AI
{
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
            return end > start ? trimmed[start..(end + 1)] : trimmed;
        }
    }
}
