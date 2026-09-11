namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.ChangeRequests
{
    /// <summary>Epic 1 - the intake record. See schema/004_change_requests.sql.</summary>
    public class ChangeRequest
    {
        public Guid Id { get; set; }
        public string RequestNumber { get; set; } = string.Empty;
        public string ChangeType { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;

        /// <summary>Raw JSON - shape varies per <see cref="ChangeType"/> (US-1.1 AC2).</summary>
        public string TypeSpecificFieldsJson { get; set; } = "{}";

        /// <summary>Submitted | InAssessment | PendingCommittee | Decisioned.</summary>
        public string Status { get; set; } = string.Empty;
        public Guid SubmittedByUserId { get; set; }
        public DateTimeOffset SubmittedAt { get; set; }
    }

    /// <summary>US-1.3 dashboard row - status + days elapsed, nothing more.</summary>
    public class ChangeRequestSummary
    {
        public Guid Id { get; set; }
        public string RequestNumber { get; set; } = string.Empty;
        public string ChangeType { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public DateTimeOffset SubmittedAt { get; set; }
        public int DaysElapsed { get; set; }
    }

    public class ChangeRequestAttachment
    {
        public Guid Id { get; set; }
        public string FileName { get; set; } = string.Empty;
        public string ContentType { get; set; } = string.Empty;
        public string StoragePath { get; set; } = string.Empty;
        public int VersionNumber { get; set; }
        public DateTimeOffset UploadedAt { get; set; }
    }

    public class ChangeRequestClarification
    {
        public Guid Id { get; set; }
        public string Question { get; set; } = string.Empty;

        /// <summary>Open | Answered.</summary>
        public string Status { get; set; } = string.Empty;
    }

    public class SubmitChangeRequestInput
    {
        public string ChangeType { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string TypeSpecificFieldsJson { get; set; } = "{}";
        public Guid SubmittedByUserId { get; set; }

        /// <summary>
        /// Optional links into Mock External Systems (Humaid.RiskGovernance.MockSystems) - which
        /// one is relevant depends on ChangeType (CustomerSegment -> customer, Product/Feature ->
        /// product, Vendor -> vendor). Null is valid for change types with no obvious linked
        /// entity (e.g. Process). See DataIngestion module - these drive the immutable snapshot
        /// captured at submission time.
        /// </summary>
        public Guid? MockCustomerId { get; set; }
        public Guid? MockProductId { get; set; }
        public Guid? MockVendorId { get; set; }
    }

    public class AttachDocumentInput
    {
        public Guid ChangeRequestId { get; set; }
        public string FileName { get; set; } = string.Empty;
        public string ContentType { get; set; } = string.Empty;
        public string StoragePath { get; set; } = string.Empty;

        /// <summary>MVP: plain-text content supplied at upload time - see architecture-mapping.md.</summary>
        public string? ExtractedText { get; set; }
        public Guid UploadedByUserId { get; set; }
        public Guid? SupersedesAttachmentId { get; set; }
    }
}
