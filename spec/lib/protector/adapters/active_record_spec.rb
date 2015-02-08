require 'spec_helpers/boot'

if defined?(ActiveRecord)
  load 'spec_helpers/adapters/active_record.rb'

  describe Protector::Adapters::ActiveRecord do
    before(:all) do
      load 'migrations/active_record.rb'

      module ProtectionCase
        extend ActiveSupport::Concern

        included do |klass|
          protect do |x|
            if x == '-'
              scope{ where('1=0') } 
            elsif x == '+'
              scope{ where(klass.table_name => {number: 999}) }
            end

            can :read, :dummy_id unless x == '-'
          end
        end
      end

      [Dummy, Fluffy].each{|c| c.send :include, ProtectionCase}

      Dummy.create! string: 'zomgstring', number: 999, text: 'zomgtext'
      Dummy.create! string: 'zomgstring', number: 999, text: 'zomgtext'
      Dummy.create! string: 'zomgstring', number: 777, text: 'zomgtext'
      Dummy.create! string: 'zomgstring', number: 777, text: 'zomgtext'

      [Fluffy, Bobby].each do |m|
        m.create! string: 'zomgstring', number: 999, text: 'zomgtext', dummy_id: 1
        m.create! string: 'zomgstring', number: 777, text: 'zomgtext', dummy_id: 1
        m.create! string: 'zomgstring', number: 999, text: 'zomgtext', dummy_id: 2
        m.create! string: 'zomgstring', number: 777, text: 'zomgtext', dummy_id: 2
      end

      Fluffy.all.each{|f| Loony.create! fluffy_id: f.id, string: 'zomgstring' }
    end

    let(:dummy) do
      Class.new(ActiveRecord::Base) do
        def self.name; 'Dummy'; end
        def self.model_name; ActiveModel::Name.new(self, nil, "dummy"); end
        self.table_name = "dummies"
        scope :none, where('1 = 0') unless respond_to?(:none)
      end
    end

    describe Protector::Adapters::ActiveRecord do
      it "finds out whether object is AR relation" do
        expect(Protector::Adapters::ActiveRecord.is?(Dummy)).to be true
        expect(Protector::Adapters::ActiveRecord.is?(Dummy.every)).to be true
      end

      it "sets the adapter" do
        expect(Dummy.restrict!('!').protector_meta.adapter).to be Protector::Adapters::ActiveRecord
      end
    end

    #
    # Model instance
    #
    describe Protector::Adapters::ActiveRecord::Base do
      it "includes" do
        expect(Dummy.ancestors).to include(Protector::Adapters::ActiveRecord::Base)
      end

      it "scopes" do
        scope = Dummy.restrict!('!')
        expect(scope).to be_a_kind_of ActiveRecord::Relation
        expect(scope.protector_subject).to eq '!'
      end

      it_behaves_like "a model"

      it "validates on create" do
        dummy.instance_eval do
          protect do; end
        end

        instance = dummy.restrict!('!').create(string: 'test')
        expect(instance.errors[:base]).to eq ["Access denied to 'string'"]
        instance.delete
      end

      it "validates on create!" do
        dummy.instance_eval do
          protect do; end
        end

        expect { dummy.restrict!('!').create!(string: 'test').delete }.to raise_error
      end

      it "validates on new{}" do
        dummy.instance_eval do
          protect do; end
        end

        result = dummy.restrict!('!').new do |instance|
          expect(instance.protector_subject).to eq '!'
        end

        expect(result.protector_subject).to eq '!'
      end

      it "finds with scope on id column" do
        dummy.instance_eval do
          protect do
            scope { where(id: 1) }
          end
        end

        expect { dummy.restrict!('!').find(1) }.to_not raise_error
        expect { dummy.restrict!('!').find(2) }.to raise_error
      end

      it "allows for validations" do
        dummy.instance_eval do
          validates :string, presence: true
          protect do; can :create; end
        end

        instance = dummy.restrict!('!').new(string: 'test')
        expect(instance.save).to be true
        instance.delete
      end
    end

    #
    # Model scope
    #
    describe Protector::Adapters::ActiveRecord::Relation do
      it "includes" do
        expect(Dummy.none.ancestors).to include(Protector::Adapters::ActiveRecord::Base)
      end

      it "saves subject" do
        expect(Dummy.restrict!('!').where(number: 999).protector_subject).to eq '!'
        expect(Dummy.restrict!('!').except(:order).protector_subject).to eq '!'
        expect(Dummy.restrict!('!').only(:order).protector_subject).to eq '!'
      end

      it "forwards subject" do
        expect(Dummy.restrict!('!').where(number: 999).first.protector_subject).to eq '!'
        expect(Dummy.restrict!('!').where(number: 999).to_a.first.protector_subject).to eq '!'
        expect(Dummy.restrict!('!').new.protector_subject).to eq '!'
        expect(Dummy.restrict!('!').first.fluffies.new.protector_subject).to eq '!'
        expect(Dummy.first.fluffies.restrict!('!').new.protector_subject).to eq '!'
      end

      it "checks creatability" do
        expect(Dummy.restrict!('!').creatable?).to eq false
        expect(Dummy.restrict!('!').where(number: 999).creatable?).to eq false
      end

      context "with open relation" do
        context "adequate", paranoid: false do

          it "checks existence" do
            expect(Dummy).to exist
            expect(Dummy.restrict!('!')).to exist
          end

          it "counts" do
            expect(Dummy.count).to eq 4
            dummy = Dummy.restrict!('!')
            expect(dummy.count).to eq 4
            expect(dummy.protector_subject?).to eq true
          end

          it "fetches" do
            fetched = Dummy.restrict!('!').to_a

            expect(Dummy.count).to eq 4
            expect(fetched.length).to eq 4
          end
        end

        context "paranoid", paranoid: true do
          it "checks existence" do
            expect(Dummy).to exist
            expect(Dummy.restrict!('!')).not_to exist
          end

          it "counts" do
            expect(Dummy.count).to be 4
            dummy = Dummy.restrict!('!')
            expect(dummy.count).to be 0
            expect(dummy.protector_subject?).to be true
          end

          it "fetches" do
            fetched = Dummy.restrict!('!').to_a

            expect(Dummy.count).to be 4
            expect(fetched.length).to be 0
          end
        end
      end

      context "with null relation" do
        it "checks existence" do
          expect(Dummy).to exist
          expect(Dummy.restrict!('!')).not_to exist
        end

        it "counts" do
          expect(Dummy.count).to eq 4
          dummy = Dummy.restrict!('-')
          expect(dummy.count).to eq 0
          expect(dummy.protector_subject?).to eq true
        end

        it "fetches" do
          fetched = Dummy.restrict!('-').to_a

          expect(Dummy.count).to eq 4
          expect(fetched.length).to eq 0
        end

        it "keeps security scope when unscoped" do
          expect(Dummy.unscoped.restrict!('-').count).to eq 0
          expect(Dummy.restrict!('-').unscoped.count).to eq 0
        end
      end

      context "with active relation" do
        it "checks existence" do
          expect(Dummy).to exist
          expect(Dummy.restrict!('+')).to exist
        end

        it "counts" do
          expect(Dummy.count).to eq 4
          dummy = Dummy.restrict!('+')
          expect(dummy.count).to eq 2
          expect(dummy.protector_subject?).to eq true
        end

        it "fetches" do
          fetched = Dummy.restrict!('+').to_a

          expect(Dummy.count).to eq 4
          expect(fetched.length).to eq 2
        end

        it "keeps security scope when unscoped" do
          expect(Dummy.unscoped.restrict!('+').count).to eq 2
          expect(Dummy.restrict!('+').unscoped.count).to eq 2
        end
      end
    end

    #
    # Model scope
    #
    describe Protector::Adapters::ActiveRecord::Association do
      describe "validates on create! within association" do
        it "when restricted from entity" do
          expect { Dummy.first.restrict!('-').fluffies.create!(string: 'test').delete }.to raise_error
        end

        it "when restricted from association" do
          expect { Dummy.first.fluffies.restrict!('-').create!(string: 'test').delete }.to raise_error
        end
      end

      context "singular association" do
        it "forwards subject" do
          expect(Fluffy.restrict!('!').first.dummy.protector_subject).to eq '!'
          expect(Fluffy.first.restrict!('!').dummy.protector_subject).to eq '!'
        end

        it "forwards cached subject" do
          expect(Dummy.first.fluffies.restrict!('!').first.dummy.protector_subject).to eq '!'
        end
      end

      context "collection association" do
        it "forwards subject" do
          expect(Dummy.restrict!('!').first.fluffies.protector_subject).to eq '!'
          expect(Dummy.first.restrict!('!').fluffies.protector_subject).to eq '!'
          expect(Dummy.restrict!('!').first.fluffies.new.protector_subject).to eq '!'
          expect(Dummy.first.restrict!('!').fluffies.new.protector_subject).to eq '!'
          expect(Dummy.first.fluffies.restrict!('!').new.protector_subject).to eq '!'
        end

        context "with open relation" do
          context "adequate", paranoid: false do

            it "checks existence" do
              expect(Dummy.first.fluffies).to exist
              expect(Dummy.first.restrict!('!').fluffies).to exist
              expect(Dummy.first.fluffies.restrict!('!')).to exist
            end

            it "counts" do
              expect(Dummy.first.fluffies.count).to be 2

              fluffies = Dummy.first.restrict!('!').fluffies
              expect(fluffies.count).to eq  2
              expect(fluffies.protector_subject?).to eq true

              fluffies = Dummy.first.fluffies.restrict!('!')
              expect(fluffies.count).to eq 2
              expect(fluffies.protector_subject?).to eq true
            end

            it "fetches" do
              expect(Dummy.first.fluffies.count).to eq 2
              expect(Dummy.first.restrict!('!').fluffies.length).to eq 2
              expect(Dummy.first.fluffies.restrict!('!').length).to eq 2
            end
          end

          context "paranoid", paranoid: true do
            it "checks existence" do
              expect(Dummy.first.fluffies.any?).to eq true
              expect(Dummy.first.restrict!('!').fluffies).not_to exist
              expect(Dummy.first.fluffies.restrict!('!')).not_to exist
            end

            it "counts" do
              expect(Dummy.first.fluffies.count).to eq 2

              fluffies = Dummy.first.restrict!('!').fluffies
              expect(fluffies.count).to be 0
              expect(fluffies.protector_subject?).to eq true

              fluffies = Dummy.first.fluffies.restrict!('!')
              expect(fluffies.count).to be 0
              expect(fluffies.protector_subject?).to eq true
            end

            it "fetches" do
              expect(Dummy.first.fluffies.count).to eq 2
              expect(Dummy.first.restrict!('!').fluffies.length).to eq 0
              expect(Dummy.first.fluffies.restrict!('!').length).to eq 0
            end
          end
        end
      end

      context "with null relation" do
        it "checks existence" do
          expect(Dummy.first.fluffies).to exist
          expect(Dummy.first.restrict!('-').fluffies).not_to exist
          expect(Dummy.first.fluffies.restrict!('-')).not_to exist
        end

        it "counts" do
          expect(Dummy.first.fluffies.count).to eq 2

          fluffies = Dummy.first.restrict!('-').fluffies
          expect(fluffies.count).to eq 0
          expect(fluffies.protector_subject?).to eq true

          fluffies = Dummy.first.fluffies.restrict!('-')
          expect(fluffies.count).to eq 0
          expect(fluffies.protector_subject?).to eq true
        end

        it "fetches" do
          expect(Dummy.first.fluffies.count).to eq 2
          expect(Dummy.first.restrict!('-').fluffies.length).to eq 0
          expect(Dummy.first.fluffies.restrict!('-').length).to eq 0
        end
      end

      context "with active relation" do
        it "checks existence" do
          expect(Dummy.first.fluffies.any?).to eq true
          expect(Dummy.first.restrict!('+').fluffies).to exist
          expect(Dummy.first.fluffies.restrict!('+')).to exist
        end

        it "counts" do
          expect(Dummy.first.fluffies.count).to eq 2

          fluffies = Dummy.first.restrict!('+').fluffies
          expect(fluffies.count).to be 1
          expect(fluffies.protector_subject?).to eq true

          fluffies = Dummy.first.fluffies.restrict!('+')
          expect(fluffies.count).to be 1
          expect(fluffies.protector_subject?).to eq true
        end

        it "fetches" do
          expect(Dummy.first.fluffies.count).to eq 2
          expect(Dummy.first.restrict!('+').fluffies.length).to eq 1
          expect(Dummy.first.fluffies.restrict!('+').length).to eq 1
        end
      end
    end

    #
    # Eager loading
    #
    describe Protector::Adapters::ActiveRecord::Preloader do
      describe "eager loading" do
        it "scopes" do
          d = Dummy.restrict!('+').includes(:fluffies)
          expect(d.length).to eq 2
          expect(d.first.fluffies.length).to eq 1
        end

        context "joined to filtered association" do
          it "scopes" do
            d = Dummy.restrict!('+').includes(:fluffies).where(fluffies: {string: 'zomgstring'})
            expect(d.length).to eq 2
            expect(d.first.fluffies.length).to eq 1
          end
        end

        context "joined to plain association" do
          it "scopes" do
            d = Dummy.restrict!('+').includes(:bobbies, :fluffies).where(
              bobbies: {string: 'zomgstring'}, fluffies: {string: 'zomgstring'}
            )
            expect(d.length).to eq 2
            expect(d.first.fluffies.length).to eq 1
            expect(d.first.bobbies.length).to eq 2
          end
        end

        context "with complex include" do
          it "scopes" do
            d = Dummy.restrict!('+').includes(fluffies: :loony).where(
              fluffies: {string: 'zomgstring'},
              loonies: {string: 'zomgstring'}
            )
            expect(d.length).to be 2
            expect(d.first.fluffies.length).to eq 1
            expect(d.first.fluffies.first.loony).to be_a_kind_of(Loony)
          end
        end
      end

      context "complicated features" do
        # https://github.com/inossidabile/protector/commit/7ce072aa2074e0f3b48e293b952810f720bc143d
        it "handles scopes with includes" do
          fluffy = Class.new(ActiveRecord::Base) do
            def self.name; 'Fluffy'; end
            def self.model_name; ActiveModel::Name.new(self, nil, "fluffy"); end
            self.table_name = "fluffies"
            scope :none, where('1 = 0') unless respond_to?(:none)
            belongs_to :dummy, class_name: 'Dummy'

            protect do
              scope { includes(:dummy).where(dummies: {id: 1}) }
            end
          end

          expect { fluffy.restrict!('!').to_a }.to_not raise_error
        end

        # https://github.com/inossidabile/protector/issues/42
        if ActiveRecord::Base.respond_to?(:enum)
          context "enums" do
            before(:each) do
              dummy.instance_eval do
                enum number: [ :active, :archived ]
              end
            end

            it "can be read" do
              dummy.instance_eval do
                protect do
                  can :read, :number
                  can :create, :number
                  can :update, :number
                end
              end

              d = dummy.new.restrict!('!')

              expect { d.active! }.to_not raise_error

              expect(d.number).to eq 'active'
              expect(d.active?).to eq true
              expect(d.archived?).to eq false

              d.delete
            end
          end
        end
      end
    end
  end

end