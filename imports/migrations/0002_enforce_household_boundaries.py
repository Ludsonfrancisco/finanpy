# ruff: noqa: E501, I001

from django.db import migrations


CREATE_TRIGGERS = """
CREATE TRIGGER imports_account_link_household_insert
BEFORE INSERT ON imports_importaccountlink
WHEN (SELECT household_id FROM accounts_account WHERE id = NEW.account_id)
     != NEW.household_id
BEGIN
    SELECT RAISE(ABORT, 'import account link crosses household boundary');
END;

CREATE TRIGGER imports_account_link_household_update
BEFORE UPDATE ON imports_importaccountlink
WHEN (SELECT household_id FROM accounts_account WHERE id = NEW.account_id)
     != NEW.household_id
BEGIN
    SELECT RAISE(ABORT, 'import account link crosses household boundary');
END;

CREATE TRIGGER imports_batch_household_insert
BEFORE INSERT ON imports_importbatch
WHEN (SELECT household_id FROM api_devicesession WHERE uuid = NEW.device_session_id)
         != NEW.household_id
     OR (
         NEW.account_id IS NOT NULL
         AND (SELECT household_id FROM accounts_account WHERE id = NEW.account_id)
             != NEW.household_id
     )
     OR (
         NEW.financial_owner_id IS NOT NULL
         AND (
             SELECT household_id
             FROM households_financialowner
             WHERE id = NEW.financial_owner_id
         ) != NEW.household_id
     )
BEGIN
    SELECT RAISE(ABORT, 'import batch crosses household boundary');
END;

CREATE TRIGGER imports_batch_household_update
BEFORE UPDATE ON imports_importbatch
WHEN (SELECT household_id FROM api_devicesession WHERE uuid = NEW.device_session_id)
         != NEW.household_id
     OR (
         NEW.account_id IS NOT NULL
         AND (SELECT household_id FROM accounts_account WHERE id = NEW.account_id)
             != NEW.household_id
     )
     OR (
         NEW.financial_owner_id IS NOT NULL
         AND (
             SELECT household_id
             FROM households_financialowner
             WHERE id = NEW.financial_owner_id
         ) != NEW.household_id
     )
BEGIN
    SELECT RAISE(ABORT, 'import batch crosses household boundary');
END;

CREATE TRIGGER imports_record_household_insert
BEFORE INSERT ON imports_importrecord
WHEN NEW.transaction_id IS NOT NULL
     AND (SELECT household_id FROM transactions_transaction WHERE id = NEW.transaction_id)
         != (SELECT household_id FROM imports_importbatch WHERE id = NEW.batch_id)
BEGIN
    SELECT RAISE(ABORT, 'import record crosses household boundary');
END;

CREATE TRIGGER imports_record_household_update
BEFORE UPDATE ON imports_importrecord
WHEN NEW.transaction_id IS NOT NULL
     AND (SELECT household_id FROM transactions_transaction WHERE id = NEW.transaction_id)
         != (SELECT household_id FROM imports_importbatch WHERE id = NEW.batch_id)
BEGIN
    SELECT RAISE(ABORT, 'import record crosses household boundary');
END;

CREATE TRIGGER imports_source_reference_household_insert
BEFORE INSERT ON imports_sourcereference
WHEN (SELECT household_id FROM accounts_account WHERE id = NEW.account_id)
     != (SELECT household_id FROM transactions_transaction WHERE id = NEW.transaction_id)
BEGIN
    SELECT RAISE(ABORT, 'source reference crosses household boundary');
END;

CREATE TRIGGER imports_source_reference_household_update
BEFORE UPDATE ON imports_sourcereference
WHEN (SELECT household_id FROM accounts_account WHERE id = NEW.account_id)
     != (SELECT household_id FROM transactions_transaction WHERE id = NEW.transaction_id)
BEGIN
    SELECT RAISE(ABORT, 'source reference crosses household boundary');
END;
"""


DROP_TRIGGERS = """
DROP TRIGGER imports_account_link_household_insert;
DROP TRIGGER imports_account_link_household_update;
DROP TRIGGER imports_batch_household_insert;
DROP TRIGGER imports_batch_household_update;
DROP TRIGGER imports_record_household_insert;
DROP TRIGGER imports_record_household_update;
DROP TRIGGER imports_source_reference_household_insert;
DROP TRIGGER imports_source_reference_household_update;
"""


class Migration(migrations.Migration):
    dependencies = [('imports', '0001_initial')]

    operations = [migrations.RunSQL(CREATE_TRIGGERS, DROP_TRIGGERS)]
