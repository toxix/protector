shared_examples_for "a model" do
  it "evaluates meta properly" do
    dummy.instance_eval do
      protect do |subject, entry|
        #expect(subject).to eq '!'
        raise "wrong subject" if subject != '!'
        raise "entry shouldn't be an protector_subject" if entry.protector_subject? != false
        #expect(entry.protector_subject?).to eq false

        scope { limit(5) }

        can :read
        can :create
        can :update
      end
    end

    fields = Hash[*%w(id string number text dummy_id).map{|x| [x, nil]}.flatten]
    meta   = dummy.new.restrict!('!').protector_meta

    expect(meta.access[:read]  ).to eq fields
    expect(meta.access[:create]).to eq fields
    expect(meta.access[:update]).to eq fields
  end

  it "respects inheritance" do
    dummy.instance_eval do
      protect do
        can :read, :test
      end
    end

    attempt = Class.new(dummy) do
      protect do
        can :create, :test
      end
    end

    expect(dummy.protector_meta.evaluate(nil, nil).access).to eq( {read: {"test"=>nil}} )
    expect(attempt.protector_meta.evaluate(nil, nil).access).to eq( {read: {"test"=>nil}, create: {"test"=>nil}} )
  end

  it "drops meta on restrict" do
    d = Dummy.first

    d.restrict!('!').protector_meta
    expect(d.instance_variable_get('@protector_meta')).not_to be_nil
    d.restrict!('!')
    expect(d.instance_variable_get('@protector_meta')).to be_nil
  end

  it "doesn't get stuck with non-existing tables" do
    Rumba.class_eval do
      protect do
      end
    end
  end

  describe "visibility" do
    it "marks blocked" do
      expect(Dummy.first.restrict!('-').visible?).to eq false
    end

    context "adequate", paranoid: false do
      it "marks allowed" do
        expect(Dummy.first.restrict!('!').visible?).to eq true
        expect(Dummy.first.restrict!('+').visible?).to eq true
      end
    end

    context "paranoid", paranoid: true do
      it "marks allowed" do
        expect(Dummy.first.restrict!('!').visible?).to eq false
        expect(Dummy.first.restrict!('+').visible?).to eq true
      end
    end
  end

  #
  # Reading
  #
  describe "readability" do
    it "hides fields" do
      dummy.instance_eval do
        protect do
          can :read, :string
        end
      end

      d = dummy.first.restrict!('!')
      expect(d.number).to be_nil
      expect(d[:number]).to be_nil
      expect(read_attribute(d, :number)).not_to be_nil
      expect(d.string).to eq 'zomgstring'
    end

    it "shows fields" do
      dummy.instance_eval do
        protect do
          can :read, :number
        end
      end

      d = dummy.first.restrict!('!')
      expect(d.number).not_to be_nil
      expect(d[:number]).not_to be_nil
      expect(d['number']).not_to be_nil
      expect(read_attribute(d, :number)).not_to be_nil
    end
  end

  #
  # Creating
  #
  describe "creatability" do
    context "with empty meta" do
      before(:each) do
        dummy.instance_eval do
          protect do; end
        end
      end

      it "handles empty creations" do
        d = dummy.new.restrict!('!')
        expect(d.can?(:create)).to eq false
        expect(d.creatable?).to eq false
        expect(d).to invalidate
      end

      it "marks blocked" do
        d = dummy.new(string: 'bam', number: 1)
        expect(d.restrict!('!').creatable?).to eq false
      end

      it "invalidates" do
        d = dummy.new(string: 'bam', number: 1).restrict!('!')
        expect(d).to invalidate
      end
    end

    context "by list of fields" do
      before(:each) do
        dummy.instance_eval do
          protect do
            can :create, :string
          end
        end
      end

      it "marks blocked" do
        d = dummy.new(string: 'bam', number: 1).restrict!('!')
        expect(d.creatable?).to eq false
      end

      it "marks allowed" do
        d = dummy.new(string: 'bam').restrict!('!')
        $debug = true
        expect(d.creatable?).to eq true
      end

      it "invalidates" do
        d = dummy.new(string: 'bam', number: 1).restrict!('!')
        expect(d).to invalidate
      end

      it "validates" do
        d = dummy.new(string: 'bam').restrict!('!')
        expect(d).to validate
      end
    end

    context "by lambdas" do
      before(:each) do
        dummy.instance_eval do
          protect do
            can :create, string: lambda {|x| x.try(:length) == 5 }
          end
        end
      end

      it "marks blocked" do
        d = dummy.new(string: 'bam')
        expect(d.restrict!('!').creatable?).to eq false
      end

      it "marks allowed" do
        d = dummy.new(string: '12345')
        expect(d.restrict!('!').creatable?).to eq true
      end

      it "invalidates" do
        d = dummy.new(string: 'bam').restrict!('!')
        expect(d).to invalidate
      end

      it "validates" do
        d = dummy.new(string: '12345').restrict!('!')
        expect(d).to validate
      end
    end

    context "by ranges" do
      before(:each) do
        dummy.instance_eval do
          protect do
            can :create, number: 0..2
          end
        end
      end

      it "marks blocked" do
        d = dummy.new(number: 500)
        expect(d.restrict!('!').creatable?).to eq false
      end

      it "marks allowed" do
        d = dummy.new(number: 2)
        expect(d.restrict!('!').creatable?).to eq true
      end

      it "invalidates" do
        d = dummy.new(number: 500).restrict!('!')
        expect(d).to invalidate
      end

      it "validates" do
        d = dummy.new(number: 2).restrict!('!')
        expect(d).to validate
      end
    end

    context "by direct values" do
      before(:each) do
        dummy.instance_eval do
          protect do
            can :create, number: 5
          end
        end
      end

      it "marks blocked" do
        d = dummy.new(number: 500)
        expect(d.restrict!('!').creatable?).to eq false
      end

      it "marks allowed" do
        d = dummy.new(number: 5)
        expect(d.restrict!('!').creatable?).to eq true
      end

      it "invalidates" do
        d = dummy.new(number: 500).restrict!('!')
        expect(d).to invalidate
      end

      it "validates" do
        d = dummy.new(number: 5).restrict!('!')
        expect(d).to validate
      end
    end
  end

  #
  # Updating
  #
  describe "updatability" do
    context "with empty meta" do
      before(:each) do
        dummy.instance_eval do
          protect do; end
        end
      end

      it "marks blocked" do
        d = dummy.first
        assign!(d, string: 'bam', number: 1)
        expect(d.restrict!('!').updatable?).to eq false
      end

      it "invalidates" do
        d = dummy.first.restrict!('!')
        assign!(d, string: 'bam', number: 1)
        expect(d).to invalidate
      end
    end

    context "by list of fields" do
      before(:each) do
        dummy.instance_eval do
          protect do
            can :update, :string
          end
        end
      end

      it "marks blocked" do
        d = dummy.first
        assign!(d, string: 'bam', number: 1)
        expect(d.restrict!('!').updatable?).to eq false
      end

      it "marks allowed" do
        d = dummy.first
        assign!(d, string: 'bam')
        expect(d.restrict!('!').updatable?).to eq true
      end

      it "invalidates" do
        d = dummy.first.restrict!('!')
        assign!(d, string: 'bam', number: 1)
        expect(d).to invalidate
      end

      it "validates" do
        d = dummy.first.restrict!('!')
        assign!(d, string: 'bam')
        expect(d).to validate
      end
    end

    context "by lambdas" do
      before(:each) do
        dummy.instance_eval do
          protect do
            can :update, string: lambda {|x| x.try(:length) == 5 }
          end
        end
      end

      it "marks blocked" do
        d = dummy.first
        assign!(d, string: 'bam')
        expect(d.restrict!('!').updatable?).to eq false
      end

      it "marks allowed" do
        d = dummy.first
        assign!(d, string: '12345')
        expect(d.restrict!('!').updatable?).to eq true
      end

      it "invalidates" do
        d = dummy.first.restrict!('!')
        assign!(d, string: 'bam')
        expect(d).to invalidate
      end

      it "validates" do
        d = dummy.first.restrict!('!')
        assign!(d, string: '12345')
        expect(d).to validate
      end
    end

    context "by ranges" do
      before(:each) do
        dummy.instance_eval do
          protect do
            can :update, number: 0..2
          end
        end
      end

      it "marks blocked" do
        d = dummy.first
        assign!(d, number: 500)
        expect(d.restrict!('!').updatable?).to eq false
      end

      it "marks allowed" do
        d = dummy.first
        assign!(d, number: 2)
        expect(d.restrict!('!').updatable?).to eq true
      end

      it "invalidates" do
        d = dummy.first.restrict!('!')
        assign!(d, number: 500)
        expect(d).to invalidate
      end

      it "validates" do
        d = dummy.first.restrict!('!')
        assign!(d, number: 2)
        expect(d).to validate
      end
    end

    context "by direct values" do
      before(:each) do
        dummy.instance_eval do
          protect do
            can :update, number: 5
          end
        end
      end

      it "marks blocked" do
        d = dummy.first
        assign!(d, number: 500)
        expect(d.restrict!('!').updatable?).to eq false
      end

      it "marks allowed" do
        d = dummy.first
        assign!(d, number: 5)
        expect(d.restrict!('!').updatable?).to eq true
      end

      it "invalidates" do
        d = dummy.first.restrict!('!')
        assign!(d, number: 500)
        expect(d).to invalidate
      end

      it "validates" do
        d = dummy.first.restrict!('!')
        assign!(d, number: 5)
        expect(d).to validate
      end
    end
  end

  #
  # Destroying
  #
  describe "destroyability" do
    it "marks blocked" do
      dummy.instance_eval do
        protect do; end
      end

      expect(dummy.first.restrict!('!').destroyable?).to eq false
    end

    it "marks allowed" do
      dummy.instance_eval do
        protect do; can :destroy; end
      end

      expect(dummy.first.restrict!('!').destroyable?).to eq true
    end

    it "invalidates" do
      dummy.instance_eval do
        protect do; end
      end

      d = dummy.create.restrict!('!')
      expect(d).to survive
    end

    it "validates" do
      dummy.instance_eval do
        protect do; can :destroy; end
      end

      d = dummy.create.restrict!('!')
      expect(d).to destroy
    end
  end

  #
  # Associations
  #
  describe "association" do
    context "(has_many)" do
      context "adequate", paranoid: false do
        it "loads" do
          expect(Dummy.first.restrict!('!').fluffies.length).to eq 2
          expect(Dummy.first.restrict!('+').fluffies.length).to eq 1
          expect(Dummy.first.restrict!('-').fluffies.empty?).to eq true
        end
      end
      context "paranoid", paranoid: true do
        it "loads" do
          expect(Dummy.first.restrict!('!').fluffies.empty?).to eq true
          expect(Dummy.first.restrict!('+').fluffies.length).to eq 1
          expect(Dummy.first.restrict!('-').fluffies.empty?).to eq true
        end
      end
    end

    context "(belongs_to)" do
      context "adequate", paranoid: false do
        it "passes subject" do
          expect(Fluffy.first.restrict!('!').dummy.protector_subject).to eq '!'
        end

        it "loads" do
          expect(Fluffy.first.restrict!('!').dummy).to be_a_kind_of(Dummy)
          expect(Fluffy.first.restrict!('-').dummy).to eq nil
        end
      end

      context "paranoid", paranoid: true do
        it "loads" do
          expect(Fluffy.first.restrict!('!').dummy).to eq nil
          expect(Fluffy.first.restrict!('-').dummy).to eq nil
        end
      end
    end
  end
end