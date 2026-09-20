# Identity is the only service that holds credentials. This table held a second set: an email, a
# bcrypt password_digest and a role, for signing in to an admin dashboard this service rendered
# itself. Both the dashboard and the sign-in are gone, and the API authenticates with a token minted
# by identity. (docs/BOUNDARY-DEBT.md W1)
#
# Irreversible on purpose. `down` could recreate the columns, but not the digests, and a half-restored
# credential table is worse than none: it would let someone believe sign-in still works.
class DropStaffUsers < ActiveRecord::Migration[8.1]
  def up
    drop_table :staff_users
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "staff_users held password digests. Identity owns credentials now; there is nothing to restore."
  end
end
