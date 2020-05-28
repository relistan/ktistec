require "../framework/model"

# Relationship between things.
#
class Relationship
  include Balloon::Model(Common, Polymorphic)

  @@table_name = "relationships"

  @[Persistent]
  property from_iri : String

  @[Persistent]
  property to_iri : String

  def validate
    super
    relationship = Relationship.find?(from_iri: from_iri, to_iri: to_iri, type: type)
    if relationship && relationship.id != self.id
      errors["relationship"] = ["already exists"]
    end
    errors
  end
end