# frozen_string_literal: true

CTON_SCHEMA = Cton.schema do
  object do
    key "user" do
      object do
        key "id", integer
      end
    end
  end
end
