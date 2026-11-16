// The authorization policies of the approval workflow.
//
// The same five policies exist as syntax trees in lean/Workflow/Policies.lean,
// where the proofs are about them. The differential test is what ties the two
// versions together. Lifecycle rules (is the request still open?) are not
// here: policies say who may act, the workflow says when.

// P1: any user may create a request
@id("P1")
permit (principal is User, action == Action::"createRequest", resource is Queue);

// P2: the requester may edit their own request
@id("P2")
permit (principal is User, action == Action::"editRequest", resource is Request)
when { resource.requester == principal };

// P3: approvers decide
@id("P3")
permit (principal in Group::"approvers",
        action in [Action::"approve", Action::"deny"],
        resource is Request);

// P4: segregation of duties
@id("P4")
forbid (principal, action == Action::"approve", resource is Request)
when { resource.requester == principal };

// P5: approvers may delegate their approval right
@id("P5")
permit (principal in Group::"approvers", action == Action::"delegate", resource is User);
