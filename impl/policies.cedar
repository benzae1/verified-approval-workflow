// Authorization policies of the approval workflow.
//
// The proofs use the same five policies as syntax trees in
// lean/Workflow/Policies.lean; the differential test checks that the two
// agree. The policies decide who may act. The workflow code checks whether a
// request is still open.

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
