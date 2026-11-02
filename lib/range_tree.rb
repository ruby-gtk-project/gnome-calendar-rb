# frozen_string_literal: true

require_relative 'range'

# RangeTree maps time spans to arbitrary data and answers "what is in this
# span?" cheaply. Upstream is a hand-balanced AVL tree of ranges, each node
# holding the data added at that exact range; the port keeps the same
# interface over a list held in range order, which traverses in the same
# order and answers the same queries.
#
# Several entries may share one range, and one datum may sit at several
# ranges, both of which upstream allows.
#
# Ported from upstream's src/core/gcal-range-tree.c.
#
class RangeTree
  Entry = Struct.new(:range, :data)

  # Returned by a traversal block to carry on or to stop early, mirroring
  # upstream's GCAL_TRAVERSE_CONTINUE / GCAL_TRAVERSE_STOP.
  CONTINUE = false
  STOP = true

  def initialize
    @entries = []
  end

  # Upstream's gcal_range_tree_add_range().
  def add_range(range, data)
    index = @entries.bsearch_index { |entry| entry.range.compare(range) >= 0 } || @entries.length
    @entries.insert(index, Entry.new(range, data))
    self
  end

  # Upstream's gcal_range_tree_remove_range(): drops the one entry holding
  # @data at exactly @range.
  def remove_range(range, data)
    index = @entries.index { |entry| entry.data.equal?(data) && entry.range.compare(range).zero? }
    unless index.nil?
      @entries.delete_at(index)
    end
    self
  end

  # Upstream's gcal_range_tree_remove_data(): drops @data wherever it sits.
  def remove_data(data)
    @entries.reject! { |entry| entry.data.equal?(data) }
    self
  end

  def clear
    @entries = []
    self
  end

  def empty? = @entries.empty?

  def length = @entries.length

  # Upstream's gcal_range_tree_traverse(). The block takes the range and the
  # data, and returning STOP ends the traversal.
  def traverse(order = :in_order)
    ordered = @entries
    if order == :reverse_order
      ordered = @entries.reverse
    end

    ordered.each do |entry|
      if yield(entry.range, entry.data) == STOP
        break
      end
    end
    self
  end

  # Upstream's gcal_range_tree_copy(). The entries are shared; the list is
  # not, so adding to the copy leaves the original alone.
  def copy
    self.class.new.tap do |tree|
      @entries.each { |entry| tree.add_range(entry.range, entry.data) }
    end
  end

  # Upstream's gcal_range_tree_get_all_data(), in range order and without
  # repeating a datum that sits at several ranges.
  def all_data = @entries.map(&:data).uniq

  # Upstream's gcal_range_tree_get_data_at_range(): everything whose range
  # overlaps @range, in range order.
  def data_at_range(range)
    [].tap do |collected|
      traverse do |entry_range, data|
        overlap, position = entry_range.overlap(range)
        if overlap == CalendarRange::NO_OVERLAP && position == CalendarRange::AFTER
          next STOP
        end

        unless overlap == CalendarRange::NO_OVERLAP
          collected << data
        end
        CONTINUE
      end
    end
  end

  # Upstream's gcal_range_tree_count_entries_at_range().
  def count_entries_at_range(range)
    counter = 0
    traverse do |entry_range, _data|
      overlap, position = entry_range.overlap(range)
      if overlap == CalendarRange::NO_OVERLAP && position == CalendarRange::AFTER
        next STOP
      end

      unless overlap == CalendarRange::NO_OVERLAP
        counter += 1
      end
      CONTINUE
    end
    counter
  end

  # Upstream's gcal_range_tree_has_entries_at_range().
  def entries_at_range?(range) = count_entries_at_range(range).positive?

  # Upstream's gcal_range_tree_print(), as a string rather than a g_print.
  def to_s = @entries.map { |entry| "#{entry.range} → #{entry.data}" }.join("\n")
end
