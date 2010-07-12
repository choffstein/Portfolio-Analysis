module StringExtensions
  # max_len is string size to shorten to if self.size is longer.
  # Default value is 1/2 the self.size. abbrev_len is the length of
  # the abbreviation before or after "..." (depending on chop_start_end)
  # abbrev_len will be coerced up or down if < 0 or exceeds max_len - 3.
  # shorten_start_end is the part of the string to chop and replace with "..."
  # For example: "iwouldbereadbetterandfasterifiwasshortened" to a max_len
  # of 16, an abbrev_len of 1, and a chop_start_end of :start would end up
  # as "i...wasshortened"
  def three_dot_chop(max_len)
    return self if size <= max_len
    abbrev_len = 3
    chop_size = size - max_len

    chop_start_index = size/2 - chop_size/2 - 2
    chop_end_index = chop_size + 2
    self[chop_start_index,chop_end_index]="..."
    self
  end
end