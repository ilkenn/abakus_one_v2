/// The top of Phase 6D's minimum-safe tenant boundary — one
/// [Organization] per account, owning 1+ [Restaurant]s, each owning 1+
/// `Branch`es. `docs/decisions.md` ADR-023 is explicit this is **not** a
/// complete multi-tenant backend: no per-organization data isolation is
/// actually enforced anywhere data is stored (every repository in this
/// codebase remains a single shared in-memory store) — this is the
/// identity/boundary shape a real backend would need to start enforcing
/// isolation against, not isolation itself.
class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final int revision;

  Organization copyWith({String? name, required int revision}) {
    return Organization(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
