# ActsAsVoteable
module Juixe
  module Acts #:nodoc:
    module Voteable #:nodoc:

      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        # 
        # Options:
        #  :vote_counter  
        #     Model stores the sum of votes in the  vote counter column when the value is true. This requires a column named `vote_count` in the table corresponding to `voteable` model.
        #     You can also specify a custom vote counter column by providing a column name instead of a true/false value to this option (e.g., :vote_counter => :my_custom_counter.) 
        #     Note: Specifying a counter will add it to that model‘s list of readonly attributes using attr_readonly.
        # 
        def acts_as_voteable options={}
          has_many :votes, :as => :voteable, :dependent => :nullify
          include Juixe::Acts::Voteable::InstanceMethods
          extend  Juixe::Acts::Voteable::SingletonMethods
          if (options[:vote_counter])
            Vote.send(:include,  Juixe::Acts::Voteable::VoteCounterClassMethods) unless Vote.respond_to?(:vote_counters)
            Vote.vote_counters = [self]
            # define vote_counter_column instance method on voteable
            vote_counter_column = (options[:vote_counter] == true) ? :vote_count : options[:vote_counter] 
            define_method(:vote_counter_column) {vote_counter_column}
            define_method(:reload_vote_counter) {reload(:select => vote_counter_column.to_s)}
            attr_readonly vote_counter_column
          end
        end        
      end

      # This module contains class methods Vote class
      module VoteCounterClassMethods
        def self.included(base)
          base.class_inheritable_array(:vote_counters)
          base.after_create { |record| record.update_vote_counters(1) }
          base.before_destroy { |record| record.update_vote_counters(-1) }
        end

        def update_vote_counters direction
          klass, vtbl = self.voteable.class, self.voteable
          klass.update_counters(vtbl.id, vtbl.vote_counter_column.to_sym => (self.vote * direction) ) if self.vote_counters.any?{|c| c == klass} 
        end
      end
      
      # This module contains class methods
      module SingletonMethods
        
        # Calculate the vote counts for all voteables of my type.
        def tally(options = {})
          find(:all, options_for_tally({:order =>"count DESC" }.merge(options)))
        end

        # 
        # Options:
        #  :start_at    - Restrict the votes to those created after a certain time
        #  :end_at      - Restrict the votes to those created before a certain time
        #  :conditions  - A piece of SQL conditions to add to the query
        #  :limit       - The maximum number of voteables to return
        #  :order       - A piece of SQL to order by. Eg 'votes.count desc' or 'voteable.created_at desc'
        #  :at_least    - Item must have at least X votes
        #  :at_most     - Item may not have more than X votes
        def options_for_tally (options = {})
            options.assert_valid_keys :start_at, :end_at, :conditions, :at_least, :at_most, :order, :limit

            scope = scope(:find)
            start_at = sanitize_sql(["#{Vote.table_name}.created_at >= ?", options.delete(:start_at)]) if options[:start_at]
            end_at = sanitize_sql(["#{Vote.table_name}.created_at <= ?", options.delete(:end_at)]) if options[:end_at]

            type_and_context = "#{Vote.table_name}.voteable_type = #{quote_value(base_class.name)}"

            conditions = [
              type_and_context,
              options[:conditions],
              start_at,
              end_at
            ]

            conditions = conditions.compact.join(' AND ')
            conditions = merge_conditions(conditions, scope[:conditions]) if scope

            joins = ["LEFT OUTER JOIN #{Vote.table_name} ON #{table_name}.#{primary_key} = #{Vote.table_name}.voteable_id"]
            joins << scope[:joins] if scope && scope[:joins]
            at_least  = sanitize_sql(["COUNT(#{Vote.table_name}.id) >= ?", options.delete(:at_least)]) if options[:at_least]
            at_most   = sanitize_sql(["COUNT(#{Vote.table_name}.id) <= ?", options.delete(:at_most)]) if options[:at_most]
            having    = [at_least, at_most].compact.join(' AND ')
            group_by  = "#{Vote.table_name}.voteable_id HAVING COUNT(#{Vote.table_name}.id) > 0"
            group_by << " AND #{having}" unless having.blank?

            { :select     => "#{table_name}.*, COUNT(#{Vote.table_name}.id) AS count", 
              :joins      => joins.join(" "),
              :conditions => conditions,
              :group      => group_by
            }.update(options)          
        end
      end
      
      # This module contains instance methods
      module InstanceMethods
        def votes_for
          self.votes.count(:conditions => {:vote => 1})
        end
        
        def votes_against
          self.votes.count(:conditions => {:vote => -1})
        end
        
        # Same as voteable.votes.size
        def votes_count
          self.votes.size
        end

        def votes_total
          self.votes.sum(:vote)
        end
        
        def voters_who_voted
          self.votes.collect(&:voter)
        end
        
        def voted_by?(voter, for_or_against = "all")
          options = {:vote => (for_or_against ? 1 : -1)} unless (for_or_against == "all")
          self.votes.exists?({:voter_id => voter.id, :voter_type => voter.class.name}.merge(options||{}))
        end
      end
    end
  end
end
