require 'spec_helpers/boot'

describe Protector::DSL do
  describe Protector::DSL::Base do
    before :each do
      @base = Class.new{ include Protector::DSL::Base }
    end

    it "defines proper methods" do
      expect(@base.instance_methods).to include(:restrict!)
      expect(@base.instance_methods).to include(:protector_subject)
    end

    it "throws error for empty subect" do
      base = @base.new
      expect { base.protector_subject }.to raise_error
    end

    it "accepts nil as a subject" do
      base = @base.new.restrict!(nil)
      expect { base.protector_subject }.to_not raise_error
    end

    it "remembers protection subject" do
      base = @base.new
      base.restrict!("universe")
      expect(base.protector_subject).to eq "universe"
    end

    it "forgets protection subject" do
      base = @base.new
      base.restrict!("universe")
      expect(base.protector_subject).to eq "universe"
      base.unrestrict!
      expect { base.protector_subject }.to raise_error
    end

    it "respects `insecurely`" do
      base = @base.new
      base.restrict!("universe")

      expect(base.protector_subject?).to eq true
      Protector.insecurely do
        expect(base.protector_subject?).to eq false
      end
    end

    it "allows nesting of `insecurely`" do
      base = @base.new
      base.restrict!("universe")

      expect(base.protector_subject?).to eq true
      Protector.insecurely do
        Protector.insecurely do
          expect(base.protector_subject?).to eq false
        end
      end
    end
  end

  describe Protector::DSL::Entry do
    before :each do
      @entry = Class.new do
        include Protector::DSL::Entry

        def self.protector_meta
          @protector_meta ||= Protector::DSL::Meta.new(nil, nil){[]}
        end
      end
    end

    it "instantiates meta entity" do
      @entry.instance_eval do
        protect do; end
      end

      expect(@entry.protector_meta).to be_an_instance_of(Protector::DSL::Meta)
    end
  end

  describe Protector::DSL::Meta do
    context "basic methods" do
      l = lambda {|x| x > 4}

      before :each do
        @meta = Protector::DSL::Meta.new(nil, nil){%w(field1 field2 field3 field4 field5)}
        @meta << lambda {
          can :read
        }

        @meta << lambda {|user|
          scope { 'relation' } if user
        }

        @meta << lambda {|user|
          raise "wrong user" if user && user != 'user'

          cannot :read, %w(field5), :field4
        }

        @meta << lambda {|user, entry|
          raise "wrong user" if user && user != 'user'
          raise "wrong entry" if user && entry != 'entry'

          can :update, %w(field1 field2),
            field3: 1,
            field4: 0..5,
            field5: l

          can :destroy
        }
      end

      it "evaluates" do
        @meta.evaluate('user', 'entry')
      end

      context "adequate", paranoid: false do
        it "sets scoped?" do
          data = @meta.evaluate(nil, 'entry')
          expect(data.scoped?).to eq false
        end
      end

      context "paranoid", paranoid: true do
        it "sets scoped?" do
          data = @meta.evaluate(nil, 'entry')
          expect(data.scoped?).to eq true
        end
      end

      context "evaluated" do
        let(:data) { @meta.evaluate('user', 'entry') }

        it "sets relation" do
          expect(data.relation).to eq 'relation'
        end

        it "sets access" do
          expect(data.access).to eq({
            update: {
              "field1" => nil,
              "field2" => nil,
              "field3" => 1,
              "field4" => 0..5,
              "field5" => l
            },
            read: {
              "field1" => nil,
              "field2" => nil,
              "field3" => nil
            }
          })
        end

        it "marks destroyable" do
          expect(data.destroyable?).to eq true
          expect(data.can?(:destroy)).to eq true
        end

        context "marks updatable" do
          it "with defaults" do
            expect(data.updatable?).to eq true
            expect(data.can?(:update)).to eq true
          end

          it "respecting lambda", dev: true do
            expect(data.updatable?('field5' => 5)).to eq true
            expect(data.updatable?('field5' => 3)).to eq false
          end
        end

        it "gets first unupdatable field" do
          expect(data.first_unupdatable_field('field1' => 1, 'field6' => 2, 'field7' => 3)).to eq 'field6'
        end

        it "marks creatable" do
          expect(data.creatable?).to eq false
          expect(data.can?(:create)).to eq false
        end

        it "gets first uncreatable field" do
          expect(data.first_uncreatable_field('field1' => 1, 'field6' => 2)).to eq 'field1'
        end
      end
    end

    context "deprecated methods" do
      before :each do
        @meta = Protector::DSL::Meta.new(nil, nil){%w(field1 field2 field3)}

        @meta << lambda {
          can :view
          cannot :view, :field2
        }
      end

      it "evaluates" do
        data = ActiveSupport::Deprecation.silence { @meta.evaluate('user', 'entry') }
        expect(data.can?(:read)).to be true
        expect(data.can?(:read, :field1)).to be true
        expect(data.can?(:read, :field2)).to be false
      end
    end

    context "custom methods" do
      before :each do
        @meta = Protector::DSL::Meta.new(nil, nil){%w(field1 field2)}

        @meta << lambda {
          can :drink, :field1
          can :eat
          cannot :eat, :field1
        }
      end

      it "sets field-level restriction" do
        box = @meta.evaluate('user', 'entry')
        expect(box.can?(:drink, :field1)).to be true
        expect(box.can?(:drink)).to be true
      end

      it "sets field-level protection" do
        box = @meta.evaluate('user', 'entry')
        expect(box.can?(:eat, :field1)).to be false
        expect(box.can?(:eat)).to be true
      end
    end

    it "avoids lambdas recursion" do
      base = Class.new{ include Protector::DSL::Base }
      meta = Protector::DSL::Meta.new(nil, nil){%w(field1)}

      meta << lambda {
        can :create, field1: lambda {|x| raise "lambda recursion" if x.protector_subject? }
      }

      box = meta.evaluate('context', 'instance')
      expect{ box.creatable?('field1' => base.new.restrict!(nil)) }.not_to raise_error
    end
  end
end
