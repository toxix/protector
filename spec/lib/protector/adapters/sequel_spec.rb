require 'spec_helpers/boot'

if defined?(Sequel)
  load 'spec_helpers/adapters/sequel.rb'

  describe Protector::Adapters::Sequel do
    before(:all) do
      load 'migrations/sequel.rb'

      module ProtectionCase
        extend ActiveSupport::Concern

        included do |klass|
          protect do |x|
            scope{ where('1=0') } if x == '-'
            scope{ where("#{klass.table_name}__number".to_sym => 999) } if x == '+' 

            can :read, :dummy_id unless x == '-'
          end
        end
      end

      [Dummy, Fluffy].each{|c| c.send :include, ProtectionCase}

      Dummy.create string: 'zomgstring', number: 999, text: 'zomgtext'
      Dummy.create string: 'zomgstring', number: 999, text: 'zomgtext'
      Dummy.create string: 'zomgstring', number: 777, text: 'zomgtext'
      Dummy.create string: 'zomgstring', number: 777, text: 'zomgtext'

      [Fluffy, Bobby].each do |m|
        m.create string: 'zomgstring', number: 999, text: 'zomgtext', dummy_id: 1
        m.create string: 'zomgstring', number: 777, text: 'zomgtext', dummy_id: 1
        m.create string: 'zomgstring', number: 999, text: 'zomgtext', dummy_id: 2
        m.create string: 'zomgstring', number: 777, text: 'zomgtext', dummy_id: 2
      end

      Fluffy.all.each{|f| Loony.create fluffy_id: f.id, string: 'zomgstring' }
    end

    describe Protector::Adapters::Sequel do
      it "finds out whether object is Sequel relation" do
        expect(Protector::Adapters::Sequel.is?(Dummy)).to eq true
        expect(Protector::Adapters::Sequel.is?(Dummy.where)).to eq true
      end

      it "sets the adapter" do
        expect(Dummy.restrict!('!').protector_meta.adapter).to eq Protector::Adapters::Sequel
      end
    end


    #
    # Model instance
    #
    describe Protector::Adapters::Sequel::Model do
      let(:dummy) do
        Class.new Sequel::Model(:dummies)
      end

      it "includes" do
        expect(Dummy.ancestors).to include(Protector::Adapters::Sequel::Model)
      end

      it "scopes" do
        scope = Dummy.restrict!('!')
        expect(scope).to be_a_kind_of Sequel::Dataset
        expect(scope.protector_subject).to eq '!'
      end

      it_behaves_like "a model"
    end

    #
    # Model scope
    #
    describe Protector::Adapters::Sequel::Dataset do
      it "includes" do
        expect(Dummy.none.class.ancestors).to include(Protector::DSL::Base)
      end

      it "saves subject" do
        expect(Dummy.restrict!('!').where(number: 999).protector_subject).to eq '!'
      end

      it "forwards subject" do
        expect(Dummy.restrict!('!').where(number: 999).first.protector_subject).to eq '!'
        expect(Dummy.restrict!('!').where(number: 999).to_a.first.protector_subject).to eq '!'
        expect(Dummy.restrict!('!').eager_graph(fluffies: :loony).all.first.fluffies.first.loony.protector_subject).to eq '!'
      end

      it "checks creatability" do
        expect(Dummy.restrict!('!').creatable?).to eq false
        expect(Dummy.restrict!('!').where(number: 999).creatable?).to eq false
      end

      context "with open relation" do
        context "adequate", paranoid: false do
          it "checks existence" do
            expect(Dummy.any?).to be true
            expect(Dummy.restrict!('!').any?).to be true
          end

          it "counts" do
            expect(Dummy.count).to eq 4
            expect(Dummy.restrict!('!').count).to eq 4
          end

          it "fetches first" do
            expect(Dummy.restrict!('!').first).to be_a_kind_of(Dummy)
          end

          it "fetches all" do
            fetched = Dummy.restrict!('!').to_a

            expect(Dummy.count).to eq 4
            expect(fetched.length).to eq 4
          end
        end

        context "paranoid", paranoid: true do
          it "checks existence" do
            expect(Dummy.any?).to be true
            expect(Dummy.restrict!('!').any?).to be false
          end

          it "counts" do
            expect(Dummy.count).to eq 4
            expect(Dummy.restrict!('!').count).to eq 0
          end

          it "fetches first" do
            expect(Dummy.restrict!('!').first).to be_nil
          end

          it "fetches all" do
            fetched = Dummy.restrict!('!').to_a

            expect(Dummy.count).to eq 4
            expect(fetched.length).to eq 0
          end
        end
      end

      context "with null relation" do
        it "checks existence" do
          expect(Dummy.any?).to be true
          expect(Dummy.restrict!('-').any?).to be false
        end

        it "counts" do
          expect(Dummy.count).to eq 4
          expect(Dummy.restrict!('-').count).to eq 0
        end

        it "fetches first" do
          expect(Dummy.restrict!('-').first).to be_nil
        end

        it "fetches all" do
          fetched = Dummy.restrict!('-').to_a

          expect(Dummy.count).to eq 4
          expect(fetched.length).to eq 0
        end
      end

      context "with active relation" do
        it "checks existence" do
          expect(Dummy.any?).to be true
          expect(Dummy.restrict!('+').any?).to be true
        end

        it "counts" do
          expect(Dummy.count).to eq 4
          expect(Dummy.restrict!('+').count).to eq 2
        end

        it "fetches first" do
          expect(Dummy.restrict!('+').first).to be_a_kind_of Dummy
        end

        it "fetches all" do
          fetched = Dummy.restrict!('+').to_a

          expect(Dummy.count).to eq 4
          expect(fetched.length).to eq 2
        end
      end
    end

    #
    # Eager loading
    #
    describe Protector::Adapters::Sequel::Dataset do
      describe "eager loading" do

        context "straight" do
          it "scopes" do
            d = Dummy.restrict!('+').eager(:fluffies)
            expect(d.count).to eq 2
            expect(d.first.fluffies.length).to eq 1
          end
        end

        context "graph" do
          it "scopes" do
            d = Dummy.restrict!('+').eager_graph(fluffies: :loony)
            expect(d.count).to eq 4
            d = d.all
            expect(d.length).to eq 2 # which is terribly sick :doh:
            expect(d.first.fluffies.length).to eq 1
            expect(d.first.fluffies.first.loony).to be_a_kind_of Loony
          end
        end
      end
    end
  end

end