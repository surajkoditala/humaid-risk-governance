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
            if (!trimmed.StartsWith("```")) return trimmed;

            var firstNewline = trimmed.IndexOf('\n');
            var lastFence = trimmed.LastIndexOf("```", StringComparison.Ordinal);
            if (firstNewline < 0 || lastFence <= firstNewline) return trimmed;

            return trimmed[(firstNewline + 1)..lastFence].Trim();
        }
    }
}
