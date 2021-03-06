require File.join(File.dirname(File.expand_path(__FILE__)), "spec_helper")

describe "Shared caching behavior" do
  before do
    @db = Sequel.mock

    class ::LookupModel < ::Sequel::Model(@db)
      columns :id, :caching_model_id, :caching_model_id2
      many_to_one :caching_model
      many_to_one :caching_model2, :key=>[:caching_model_id, :caching_model_id2], :class=>:CachingModel
    end
    @c = LookupModel

    class ::CachingModel < Sequel::Model(@db)
      columns :id, :id2
    end
    @cc = CachingModel
  end
  after do
    Object.send(:remove_const, :CachingModel)
    Object.send(:remove_const, :LookupModel)
  end

  shared_examples_for "many_to_one_pk_lookup with composite keys" do
    it "should use a simple primary key lookup when retrieving many_to_one associated records with a composite key" do
      @db.sqls.should == []
      @c.load(:id=>3, :caching_model_id=>1, :caching_model_id2=>2).caching_model2.should equal(@cm12)
      @c.load(:id=>3, :caching_model_id=>2, :caching_model_id2=>1).caching_model2.should equal(@cm21)
      @db.sqls.should == []
      @cc.dataset._fetch = []
      @c.load(:id=>4, :caching_model_id=>2, :caching_model_id2=>2).caching_model2.should == nil
    end
  end

  shared_examples_for "many_to_one_pk_lookup" do
    it "should use a simple primary key lookup when retrieving many_to_one associated records" do
      @cc.set_primary_key([:id, :id2])
      @db.sqls.should == []
      @c.load(:id=>3, :caching_model_id=>1).caching_model.should equal(@cm1)
      @c.load(:id=>4, :caching_model_id=>2).caching_model.should equal(@cm2)
      @db.sqls.should == []
      @cc.dataset._fetch = []
      @c.load(:id=>4, :caching_model_id=>3).caching_model.should == nil
    end

    it "should not use a simple primary key lookup if the assocation has a nil :key option" do
      @c.many_to_one :caching_model, :key=>nil, :dataset=>proc{CachingModel.filter(:caching_model_id=>caching_model_id)}
      @c.load(:id=>3, :caching_model_id=>1).caching_model
      @db.sqls.should_not == []
    end

    it "should not use a simple primary key lookup if the assocation has a nil :key option" do
      @c.many_to_one :caching_model, :many_to_one_pk_lookup=>false
      @c.load(:id=>3, :caching_model_id=>1).caching_model
      @db.sqls.should_not == []
    end

    it "should not use a simple primary key lookup if the assocation's :primary_key option doesn't match the primary key of the associated class" do
      @c.many_to_one :caching_model, :primary_key=>:id2
      @c.load(:id=>3, :caching_model_id=>1).caching_model
      @db.sqls.should_not == []
    end

    it "should not use a simple primary key lookup if the assocation has :conditions" do
      @c.many_to_one :caching_model, :conditions=>{:a=>1}
      @c.load(:id=>3, :caching_model_id=>1).caching_model
      @db.sqls.should_not == []
    end

    it "should not use a simple primary key lookup if the assocation has :select" do
      @c.many_to_one :caching_model, :select=>[:a, :b]
      @c.load(:id=>3, :caching_model_id=>1).caching_model
      @db.sqls.should_not == []
    end

    it "should not use a simple primary key lookup if the assocation has a block" do
      @c.many_to_one(:caching_model){|ds| ds.where{a > 1}}
      @c.load(:id=>3, :caching_model_id=>1).caching_model
      @db.sqls.should_not == []
    end

    it "should not use a simple primary key lookup if the assocation has a non-default :dataset option" do
      cc = @cc
      @c.many_to_one :caching_model, :dataset=>proc{cc.where(:id=>caching_model_id)}
      @c.load(:id=>3, :caching_model_id=>1).caching_model
      @db.sqls.should_not == []
    end

    it "should use a simple primary key lookup if explicitly set" do
      @c.many_to_one :caching_model, :select=>[:a, :b], :many_to_one_pk_lookup=>true
      @c.load(:id=>3, :caching_model_id=>1).caching_model
      @db.sqls.should == []
    end

    it "should not use a simple primary key lookup if the prepared_statements_associations method is being used" do
      c2 = Class.new(Sequel::Model(@db[:not_caching_model]))
      c2.dataset._fetch = {:id=>1}
      c = Class.new(Sequel::Model(@db[:lookup_model]))
      c.class_eval do
        plugin :prepared_statements_associations
        columns :id, :caching_model_id
        many_to_one :caching_model, :class=>c2
      end
      c.load(:id=>3, :caching_model_id=>1).caching_model.should == c2.load(:id=>1)
      @db.sqls.should_not == []
    end

    it "should use a simple primary key lookup if the prepared_statements_associations method is being used but associated model also uses caching" do
      c = Class.new(Sequel::Model(:lookup_model))
      c.class_eval do
        plugin :prepared_statements_associations
        columns :id, :caching_model_id
        many_to_one :caching_model
      end
      c.load(:id=>3, :caching_model_id=>1).caching_model.should equal(@cm1)
      @db.sqls.should == []
    end
  end

  describe "With caching plugin" do
    before do
      @cache_class = Class.new(Hash) do
        attr_accessor :ttl
        def set(k, v, ttl); self[k] = v; @ttl = ttl; end
        def get(k); self[k]; end
      end
      cache = @cache_class.new
      @cache = cache
      
      @cc.plugin :caching, @cache
      @cc.dataset._fetch = {:id=>1}
      @cm1 = @cc[1]
      @cm2 = @cc[2]
      @cm12 = @cc[1, 2]
      @cm21 = @cc[2, 1]

      @db.sqls
    end

    it_should_behave_like "many_to_one_pk_lookup"
    it_should_behave_like "many_to_one_pk_lookup with composite keys"
  end

  describe "With static_cache plugin with single key" do
    before do
      @cc.dataset._fetch = [{:id=>1}, {:id=>2}]
      @cc.plugin :static_cache
      @cm1 = @cc[1]
      @cm2 = @cc[2]
      @db.sqls
    end

    it_should_behave_like "many_to_one_pk_lookup"

    it "should not issue regular query if primary key lookup returns no rows" do
      def @cc.primary_key_lookup(pk); end
      @c.many_to_one :caching_model
      @c.load(:id=>3, :caching_model_id=>1).caching_model
      @db.sqls.should == []
    end
  end

  describe "With static_cache plugin with composite key" do
    before do
      @cc.set_primary_key([:id, :id2])
      @cc.dataset._fetch = [{:id=>1, :id2=>2}, {:id=>2, :id2=>1}]
      @cc.plugin :static_cache
      @cm12 = @cc[[1, 2]]
      @cm21 = @cc[[2, 1]]
      @db.sqls
    end

    it_should_behave_like "many_to_one_pk_lookup with composite keys"
  end
end
