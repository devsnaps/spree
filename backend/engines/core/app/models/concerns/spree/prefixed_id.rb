# frozen_string_literal: true

require 'sqids'

module Spree
  # Adds Stripe-style prefixed IDs to Spree models using Sqids encoding.
  # IDs are computed on the fly from integer primary keys -- no database column needed.
  #
  # e.g., Product with id=12345 -> "prod_86Rf07xd4z"
  #
  #   class Product < Spree.base_class
  #     has_prefix_id :prod
  #   end
  module PrefixedId
    extend ActiveSupport::Concern

    SQIDS = Sqids.new(
      min_length: 12,
      alphabet: '0123456789' # Only digits, so encoded IDs will be numeric-only
    )

    included do
      class_attribute :_prefix_id_prefix, instance_writer: false
    end

    # Returns the Sqids-based ID (numeric-only in our configuration), or nil for unsaved records.
    def prefixed_id
      return nil unless id.present?

      Spree::PrefixedId::SQIDS.encode([id])
    end

    # Use prefixed_id for URL params when available.
    # Skip if FriendlyId is used (it has its own to_param using slug).
    def to_param
      return super if self.class.respond_to?(:friendly_id_config)
      return super unless self.class._prefix_id_prefix.present?

      prefixed_id.presence || super
    end

    class_methods do
      def has_prefix_id(prefix)
        self._prefix_id_prefix = prefix.to_s
      end

      def find_by_prefix_id!(prefixed_id)
        decoded = decode_prefixed_id(prefixed_id)
        raise ActiveRecord::RecordNotFound.new("Couldn't find #{name} with prefixed id=#{prefixed_id}", name) unless decoded

        find(decoded)
      end

      def find_by_prefix_id(prefixed_id)
        decoded = decode_prefixed_id(prefixed_id)
        return nil unless decoded

        find_by(id: decoded)
      end

      # Decode a prefixed ID string (e.g., "prod_86Rf07xd4z") to the integer primary key.
      def decode_prefixed_id(prefixed_id_string)
        return nil if prefixed_id_string.blank?

        str = prefixed_id_string.to_s
        parts = str.split('_', 2)
        # Support both "prefix_encoded" and bare "encoded" (numeric-only IDs without prefix)
        encoded = parts.length == 2 ? parts.last : parts.first

        ids = Spree::PrefixedId::SQIDS.decode(encoded)
        ids.first
      end

      # Find by prefixed ID first, falling back to integer id for backwards compatibility.
      def find_by_param(param)
        return nil if param.blank?

        find_by_prefix_id(param) || (find_by(id: param) if param.to_s.match?(/\A\d+\z/))
      end

      def find_by_param!(param)
        find_by_param(param) || raise(ActiveRecord::RecordNotFound.new("Couldn't find #{name} with param=#{param}", name))
      end
    end
  end
end
