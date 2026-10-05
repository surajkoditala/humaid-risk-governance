namespace Humaid.RiskGovernance.MockSystems
{
    // Field lists match both the architect's Platform Ecosystem Diagram and the 2026-09-09 sync's
    // discussion of what each mock system contributes to a change request's risk picture.

    public class MockCustomer
    {
        public Guid Id { get; set; }
        public string CustomerName { get; set; } = string.Empty;
        public string CustomerType { get; set; } = string.Empty; // Individual, SmallBusiness, Corporate, MSB, NGO
        public string CustomerGeography { get; set; } = string.Empty;
        public string SegmentClassification { get; set; } = string.Empty; // Retail, PrivateBanking, Commercial
        public string KycStatus { get; set; } = string.Empty; // Verified, Pending, Flagged
        public string? RiskFlag { get; set; } // written back by the Workbench's feedback loop (Step 5)
    }

    public class MockProduct
    {
        public Guid Id { get; set; }
        public string ProductName { get; set; } = string.Empty;
        public string ProductType { get; set; } = string.Empty; // WireTransfer, PrepaidCard, TradeFinance, ...
        public string FeaturesJson { get; set; } = "{}"; // limits etc.
        public string ProductGeography { get; set; } = string.Empty;
        public string LaunchChangeType { get; set; } = string.Empty; // New, FeatureAdd, ProcessChange
        public bool? GoLiveFlag { get; set; } // written back by the feedback loop
        public string? RiskRating { get; set; } // written back by the feedback loop
    }

    public class MockVendor
    {
        public Guid Id { get; set; }
        public string VendorName { get; set; } = string.Empty;
        public string VendorRiskRating { get; set; } = string.Empty; // as originally on file
        public string VendorJurisdiction { get; set; } = string.Empty;
        public string DataAccessScope { get; set; } = string.Empty;
        public string CertificationStatus { get; set; } = string.Empty; // Certified, Pending, None
        public string? UpdatedRiskRating { get; set; } // written back by the feedback loop
    }

    public class CustomerRiskFlagInput
    {
        public string RiskFlag { get; set; } = string.Empty;
    }

    public class ProductRiskUpdateInput
    {
        public bool GoLive { get; set; }
        public string RiskRating { get; set; } = string.Empty;
    }

    public class VendorRiskUpdateInput
    {
        public string UpdatedRiskRating { get; set; } = string.Empty;
    }
}
