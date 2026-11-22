// SAFE-1 story 03 (2026-11-21) — who OWNS each account. Founder decision D-10: add an owner role;
// the first owner is the founder (account 2 -> user 2), seeded by hand.
// Emgram had only admin and member (user.role); D-9 ("only the owner resets admins") needed an
// owner to check against. A side table, not a new enum value on user.role and not a column on
// user: updateTableSchema drops user's text validators (CLAUDE.md).
//
// The owner is still an admin in user.role; this table only ADDS "is also the owner".
// One owner per account (account_id unique); a person owns at most one account (user_id unique).
// NO endpoint writes this table. Platform support sets or moves the owner by hand, the same rule
// as user.is_platform_admin. An account with no row has no owner: admins still reset members,
// and nobody in that account can reset another admin.
//
// GOV-1: S1 primary key; S2 created_at + updated_at; S3 references declared and indexed;
// S6 unique natural keys.
table account_owner {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    timestamp updated_at?

    int account_id? {
      table = "account"
      description = "The account. Unique: one owner per account."
    }

    int user_id? {
      table = "user"
      description = "The owner. Must be a person (not an AI) in this account. Unique."
    }

    text note? filters=trim {
      description = "Why this person is the owner, e.g. 'founder, seeded 2026-11-21'."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "account_id", op: "asc"}]}
    {type: "btree|unique", field: [{name: "user_id", op: "asc"}]}
  ]
}
