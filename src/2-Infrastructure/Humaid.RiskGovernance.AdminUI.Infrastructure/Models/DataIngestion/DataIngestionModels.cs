namespace Humaid.RiskGovernance.AdminUI.Infrastructure.Models.DataIngestion
{
    /// <summary>A row from Humaid.RiskGovernance.MockSystems' /api/customers.</summary>
    public class MockCustomerContext
    {
        public Guid Id { get; set; }
        public string CustomerName { get; set; } = string.Empty;
        public string CustomerType { get; set; } = string.Empty;
        public string CustomerGeography { get; set; } = string.Empty;
        public string SegmentClassification { get; set; } = string.Empty;
        public string KycStatus { get; set; } = string.Empty;
    }

    /// <summary>A row from Humaid.RiskGovernance.MockSystems' /api/products.</summary>
    public class MockProductContext
    {
        public Guid Id { get; set; }
        public string ProductName { get; set; } = string.Empty;
        public string ProductType { get; set; } = string.Empty;
        public string ProductGeography { get; set; } = string.Empty;
        public string LaunchChangeType { get; set; } = string.Empty;
    }

    /// <summary>A row from Humaid.RiskGovernance.MockSystems' /api/vendors.</summary>
    public class MockVendorContext
    {
        public Guid Id { get; set; }
        public string VendorName { get; set; } = string.Empty;
        public string VendorRiskRating { get; set; } = string.Empty;
        public string VendorJurisdiction { get; set; } = string.Empty;
        public string DataAccessScope { get; set; } = string.Empty;
        public string CertificationStatus { get; set; } = string.Empty;
    }

    /// <summary>One entry in an Intake lookup dropdown (id + display label).</summary>
    public class MockLookupOption
    {
        public Guid Id { get; set; }
        public string Label { get; set; } = string.Empty;
    }

    /// <summary>
    /// The immutable snapshot IDataIngestionService writes at submission time - see
    /// schema/014_external_snapshot.sql. Never updated after creation; a change request either
    /// has no snapshot yet, or has exactly one, forever.
    /// </summary>
    public class ExternalSnapshot
    {
        public Guid Id { get; set; }
        public Guid ChangeRequestId { get; set; }
        public Guid? MockCustomerId { get; set; }
        public string? CustomerRiskContextJson { get; set; }
        public Guid? MockProductId { get; set; }
        public string? ProductRiskContextJson { get; set; }
        public Guid? MockVendorId { get; set; }
        public string? VendorRiskContextJson { get; set; }
        public DateTimeOffset IngestedAt { get; set; }
    }
}
