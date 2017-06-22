module SlimFormObject
  class Saver
    include ::HelperMethods

    attr_reader :form_object, :params, :validator, :hash_objects_for_save

    def initialize(form_object)
      @form_object           = form_object
      @params                = form_object.params
      @hash_objects_for_save = form_object.hash_objects_for_save
      @validator             = Validator.new(form_object)
    end

    def save
      if form_object.valid?
        ActiveRecord::Base.transaction do
          save_main_objects
          save_nested_objects
        end
        return true
      end

      false
    rescue
      false
    end

    private

    def save_main_objects
      objects = Array.new(hash_objects_for_save[:objects])
      while object_1 = objects.delete( objects[0] )
        objects.each{ |object_2| save_objects(object_1, object_2) }
        save_last_model_if_not_associations(object_1)
      end
    end

    def save_nested_objects
      hash_objects_for_save[:objects].each do |object_1|
        next unless hash_objects_for_save[:nested_objects].include?( snake(object_1.class).to_sym )
        hash_objects_for_save[:nested_objects][snake(object_1.class).to_sym].each do |object_2|
          save_objects(object_1, object_2)
        end
      end
    end

    def save_objects(object_1, object_2)
      object_for_save = to_bind_models(object_1, object_2)
      save_object(object_for_save)
    end

    def to_bind_models(object_1, object_2)
      association = get_association(object_1.class, object_2.class)

      if    association == :belongs_to or association == :has_one
        object_1.send( "#{snake(object_2.class.to_s)}=", object_2 )
      elsif association == :has_many   or association == :has_and_belongs_to_many
        object_1.method("#{object_2.class.table_name}").call << object_2
      end

      object_1
    end

    def save_object(object_of_model)
      if validator.valid_model_for_save?(object_of_model.class)
        object_of_model.save!  
      end
    end

    def save_last_model_if_not_associations(object_1)
      association_trigger  = false
      hash_objects_for_save[:objects].each { |object_2| association_trigger = true if get_association(object_1.class, object_2.class) }
      object_1.save unless association_trigger
    rescue
      object_1.class.find(object_1.id).update!(object_1.attributes)
    end

    def get_association(class1, class2)
      class1.reflections.slice(snake(class2.to_s), class2.table_name).values.first&.macro
    end

  end
end