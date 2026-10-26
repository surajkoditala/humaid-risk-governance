namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Interfaces.Ai
{
    /// <summary>
    /// Ambient "which change request is this AI call for" carried from the service that makes the
    /// call down to the provider client that records its token use. The Services and AI projects
    /// are siblings that share only this project, and <see cref="IChatCompletionClient"/> and every
    /// AI-touchpoint interface keep their signatures, so the ids travel with the async flow instead.
    /// Either id may be null; the database derives the request from the assessment when only that
    /// is known.
    /// </summary>
    public static class AiCallContext
    {
        private sealed record Values(Guid? ChangeRequestId, Guid? AssessmentId);

        private static readonly AsyncLocal<Values?> Current = new();

        public static Guid? ChangeRequestId => Current.Value?.ChangeRequestId;

        public static Guid? AssessmentId => Current.Value?.AssessmentId;

        /// <summary>Scopes the ids to the returned object; disposing restores whatever was set before.</summary>
        public static IDisposable Begin(Guid? changeRequestId, Guid? assessmentId)
        {
            var previous = Current.Value;
            Current.Value = new Values(changeRequestId, assessmentId);
            return new Scope(previous);
        }

        private sealed class Scope(Values? previous) : IDisposable
        {
            public void Dispose() => Current.Value = previous;
        }
    }
}
