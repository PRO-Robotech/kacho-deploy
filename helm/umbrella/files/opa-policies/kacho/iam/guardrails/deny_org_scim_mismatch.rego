# KAC-127 Phase 3 (acceptance §4.6 R3, design §4.1 #3)
# Deny: granting an org-wide role to a user not in the organization's SCIM-set.
#
# Rationale: org-wide roles confer access to ALL accounts/projects under an
# Organization. The SCIM-set is the authoritative "who is a member of this
# org" boundary (federated from corporate IDP). Granting org.admin to a user
# outside the SCIM-set bypasses the federated source-of-truth — possible
# insider attack vector.
#
# Helper `user_in_organization(user_id, org_id)` is data-driven: the
# kacho-iam bundle generator snapshots `scim_user_mappings` table into
# data/organizations_users.json on each bundle build.

package kacho.iam.guardrails

import rego.v1

deny contains msg if {
	input.action == "access_bindings.upsert"
	input.target.resource_type == "organization"
	org_id := input.target.resource_id
	not user_in_organization(input.target.subject_id, org_id)
	msg := sprintf("user %v not member of organization %v", [input.target.subject_id, org_id])
}

# user_in_organization(user_id, org_id) — true iff a SCIM membership exists.
# Data shape (data/organizations_users.json):
#   {"members": {"org_acme": ["usr_alice", "usr_bob"], "org_other": ["usr_charlie"]}}
user_in_organization(user_id, org_id) if {
	members := data.kacho.iam.guardrails.data.organizations_users.members[org_id]
	user_id in members
}
