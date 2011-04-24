root = exports ? this

## Import Statements

FILL_DELAY = root.FILL_DELAY
STRAT_DELAY = root.STRAT_DELAY
max_solve_iter = root.max_solve_iter

util = root.util
dom = root.dom
log = dom.log

## Solver Class ##

class Solver
  constructor: (@grid) ->

    # A Solver is constructed once every time the solve button is hit, so all
    # the relevant parameters are set to their defaults here.

    # Restrictions are indexed first by cell index and then by value
    # restricted. So `@restrictions[0]` is the array of restricted values for
    # cell 0, and `@restrictions[10][5]` is a 1 if cell 10 is restricted from
    # being value 5 or is a 0 if cell 10 is not restricted from being value 5.
    @restrictions = []
    make_empty_restriction = -> [0,0,0,0,0,0,0,0,0,0]
    @restrictions = (make_empty_restriction() for i in [0...81])

    # Clusters are indexed first by type of group (row = 0, col = 1, box = 2),
    # then by index of that group (0-8), then by value (1-9), then by positions
    # (0-8), with a 0 indicating not in the cluster and 1 indicating in the
    # cluster. For example, if `@clusters[1][3][2]` were `[1,1,1,0,0,0,0,0,0]`,
    # then the 4th row would need to have value 2 in the first 3 spots.
    @clusters = []
    make_empty_cluster = -> [0,0,0,0,0,0,0,0,0]
    make_empty_cluster_vals = -> (make_empty_cluster() for i in [1..9])
    make_empty_cluster_groups = -> (make_empty_cluster_vals() for i in [0..8])
    @clusters = (make_empty_cluster_groups() for i in [0..2])

    # Counts the iterations thrrough the loop, may be phased out in favor of
    # just stopping once have exhausted strategies. FIXME phase this out.
    @solve_iter = 0

    # Count the number of occurrences of each value.
    @occurrences = [0,0,0,0,0,0,0,0,0,0]
    for v in [1..9]
      for i in [0...81]
        @occurrences[v] += 1 if @grid.get(i) == v

    # A collection keeping track of previous success/failures of strategies.
    @prev_results = []

    # Variable to track whether the last strategy was a success or not... FIXME
    # should be phased out, is redundant with @prev_strategies
    @updated = true


  ### Variable Access ###
  # Some of the data structures used by Solver are relatively complicated and
  # structured strangely. These methods provide better interfaces for
  # interacting with (ie, getting/setting/adding to) these variables.

  # Get the list of names of previously performed strategies.
  prev_strats: ->
    strats = (@prev_results[i].strat for i in [0...@prev_results.length])

  # Adds a restriction of value v to cell with base index i. Returns whether the
  # restriction was useful information (ie, if the restriction wasn't already in
  # the database of restrictions)
  add_restriction: (i, v) ->
    # we should only be adding restrictions to cells which aren't set yet.
    throw "Error" if @grid.get(i) != 0

    prev = @restrictions[i][v]
    @restrictions[i][v] = 1
    return prev == 0

  # Gets a representation of the cell restriction for the cell with base index
  # i. If the cell has a lot of restrictions, then returns a list of values
  # which the cell must be; if the cell has only a few restrictions, then
  # returns a list of values which the cell can't be. The returned object will
  # have a "type" field specifying if it's returning the list of cells possible
  # ("must"), the list of cells not possible ("cant"), or no information because
  # no info has yet been storetd for the cell ("none"), and a "vals" array with
  # the list of values either possible or impossle.
  get_restrictions: (i) ->
    r = @restrictions[i]
    n = util.num_pos r

    if n == 0
      return { type: "none" }
    else if 1 <= n <= 4
      cants = []
      for j in [1..9]
        cants.push(j) if r[j] == 1
      return { type: "cant", vals: cants }
    else # this will mean n >= 5
      musts = []
      for j in [1..9]
        musts.push(j) if r[j] == 0
      return { type: "must", vals: musts }


  ### Setting ###

  # Wrapper for `@grid.set` which will update the knowledge base and fill in
  # values if setting this value makes others obvious. Also requires a string
  # specifying the strategy used to find this value, so that it can
  # appropriately be stored in the record (this needs to be done in the set
  # function since it recursively calls the `fill_obvious` functions).
  set: (i, v, strat) ->
    @grid.set i,v
    @record.push {type: "fill", idx: i, val: v, strat: strat}
    log "Setting (#{util.base_to_cart(i)}) to #{v} by #{strat}"

    @occurrences[v] += 1

    [x,y] = util.base_to_cart i
    [b_x,b_y,s_x,s_y] = util.base_to_box i

    @fill_obvious_row(y)
    @fill_obvious_col(x)
    @fill_obvious_box(b_x, b_y)

  # Wrapper for `@grid.set_c` which will update the knowledge base if it needs
  # to and fill in values if setting this value makes others obvious.
  set_c: (x,y,v,strat) ->
    @set(util.cart_to_base(x,y), v, strat)

  # Wrapper for `@grid.set_b` which will update the knowldege base if it needs
  # to and fill in values if setting this value makes others obvious.
  set_b: (b_x, b_y, s_x, s_y, strat) ->
    @set(util.cart_to_base util.box_to_cart(b_x, b_y, s_x, s_y)..., v, strat)

  # If the specified group of indices has only one value missing, then will fill
  # in that value.
  fill_obvious_group: (idxs, type) ->
    vals = (@grid.get(i) for i in idxs)

    if util.num_pos(vals) == 8
      # Get the value which is missing.
      v = 1
      v += 1 until v not in vals

      # Get the position which is missing a value.
      i = 0
      i += 1 until @grid.get(idxs[i]) == 0
      idx = idxs[i]

      @set(idx, v, "#{type}-obvious")

  # Calls `fill_obvious_group` for a row.
  fill_obvious_row: (y) ->
    idxs = @grid.get_row_idxs(y)
    @fill_obvious_group(idxs, "row")

  # Calls `fill_obvious_group` for a col.
  fill_obvious_col: (x) ->
    idxs = @grid.get_col_idxs(y)
    @fill_obvious_group(idxs, "col")

  # Calls `fill_obvious_group` for a box.
  fill_obvious_box: (b_x, b_y) ->
    idxs = @grid.get_box_idxs(b_x, b_y)
    @fill_obvious_group(idxs, "box")


  ### Basic Logic ###

  # Get an array of all naively impossible values to fill into the cell at base
  # index i in the grid. If the cell already has a value, then will return all
  # other values; this seems a little unnecessary, but turns out to make other
  # things cleaner.
  naive_impossible_values: (i) ->
    if @grid.get(i) > 0
      return _.without([1..9], @grid.get(i))
    else
      @grid.get_row_vals_of(i).
        concat(@grid.get_col_vals_of(i)).
          concat(@grid.get_box_vals_of(i))

  # Iets a list of positions in a specified box where v can be filled in based
  # on `naive_impossible_values`. The box can be specified either as (x,y) in
  # [0..2]x[0..2] or with a single index in [0..8]. Positions are returned as
  # base indices of the grid.
  naive_possible_positions_in_box: (v, x, y) ->
    unless y?
      y = Math.floor x / 3
      x = Math.floor x % 3

    ps = []
    for b in [0..2]
      for a in [0..2]
        i = util.box_to_base x,y,a,b
        ps.push(i) unless v in @naive_impossible_values(i)

    return ps

  # Gets a list of positions in a specified row where v can be filled in based
  # on `naive_impossible_values`. The row is specified as a y-coordinate of
  # cartesian coordinates, and positions are returned as base indices of the
  # grid.
  naive_possible_positions_in_row: (v, y) ->
    ps = []
    for x in [0..8]
      i = util.cart_to_base x,y
      ps.push(i) unless v in @naive_impossible_values(i)

    return ps

  # Gets a list of positions in a specified col where v can be filled in based
  # on `naive_impossible_values`. The row is specified as an x-coordinate of
  # cartesian coordinates, and positions are returned as base indices of the grid.
  naive_possible_positions_in_col: (v, x) ->
    ps = []
    for y in [0..8]
      i = util.cart_to_base x,y
      ps.push(i) unless v in @naive_impossible_values(i)

    return ps

  # Returns an array of values in order of the number of their occurrences,
  # in order of most prevalent to least prevalent. Only includes values which
  # occur 5 or more times.
  vals_by_occurrences_above_4: ->
    ord = []
    for o in [9..5]
      for v in [1..9]
        ord.push(v) if @occurrences[v] == o
    return ord

  # Returns an array of values in order of the number of their occurrences, in
  # order of most prevalent to least prevalent.
  vals_by_occurrences: ->
    ord = []
    for o in [9..1]
      for v in [1..9]
        ord.push(v) if @occurrences[v] == o
    return ord

  # If the base indices are all in the same row, then returns the index of that
  # row; otherwise returns false.
  same_row: (idxs) ->
    first_row = util.base_to_cart(idxs[0])[1]
    idxs = _.rest(idxs)
    for idx in idxs
      return false if util.base_to_cart(idx)[1] != first_row
    return first_row

  # If the base indices are all in the same column, then returns the index of
  # that col; otherwise returns false.
  same_col: (idxs) ->
    first_col = util.base_to_cart(idxs[0])[0]
    idxs = _.rest(idxs)
    for idx in idxs
      return false if util.base_to_cart(idx)[0] != first_col
    return first_col

  # If the base indices are all in the same box, then returns the index of that
  # box; otherwise returns false.
  same_box: (idxs) ->
    first_box = util.base_to_box(idx[0])
    idxs = _.rest(idxs)
    for idx in idxs
      box = util.base_to_box(idx)
      return false if box[0] != first_box[0] or box[1] != first_box[1]
    return first_box[0]+first_box[0]*3


  ### New Strategies ###


  #### Grid Scan ####
  # Considers each value that occurs 5 or more times, in order of currently most
  # present on the grid to currently least present (pre-computed, so adding new
  # values will not affect the order values are iterated through; this is
  # roughly similar to what a real person would do, as they would basically look
  # over the grid once, then start looking through values, keeping a mental list
  # of what values they'd already tried and not returning back to them). For
  # each value v, consider the boxes b where v has not yet been filled in.

  gridScan: ->
    @record.push {type: "strat", strat: "GridScan"}
    @prev_results.push {strat: "GridScan", vals: 0, knowledge: 0}
    result = _.last(@prev_results)
    log "Trying Grid Scan"

    vals = @vals_by_occurrences_above_4()

    for v in vals
      @record.push {type: "gridscan-val", val: v}
      log "GridScan examining value #{v}"

      # Get the boxes which don't contain v.
      boxes = []
      boxes.push(b) if v not in @grid.get_box_vals(b) for b in [0..8]

      for b in boxes
        @record.push {type: "gridscan-box", box: b}
        log "GridScan examining box #{b}"

        ps = @naive_possible_positions_in_box v, b

        if ps.length == 1
          result.vals += 1
          @set(ps[0], v, "gridScan")


  #### Smart Grid Scan ####
  # Consider each value, in order of currently most present on the grid to least
  # present (as above, with the order pre-computed). For each value v, consider
  # each box b where v has not yet been filled in. Let p be the set of positions
  # where v can be placed within b. If p is a single position, then fill in v at
  # this position (note that this is extremely similar to GridScan in this
  # case). If all the positions in p are in a single row or col, then add a
  # restriction of v to all other cells in the row or col but outside of
  # b.
  #
  # NOTE: This is mostly a knowledge refinement strategy, and the goal is to
  # only add a couple restrictions here and there, which would then be picked up
  # by ExhaustionSearch, but we will also fill in some values which Grid Scan
  # would not pick up (since we will consider something more strict than naively
  # impossible values).
  #
  # FIXME: actually consider something mroe strict than naively impossible
  # vaules, and also completely restructure this: should only store restrictions
  # if a set of restrictions already exists, and something like Exhaustion
  # Search should instead create them initially.




  # A heurisitc for whether Grid Scan should be run. Will run Grid Scan if no
  # other strategies have been tried, or if the last operation was a Grid Scan
  # and it worked (meaning it set at least one value).
  should_gridScan: ->
    if @prev_results.length == 0
      return true
    else
      last = _.last(@prev_results)
      return last.strat == "GridScan" and last.num_set > 0

  choose_strategy: ->
    # FIXME: should make this more complicated, maybe choose order to test based
    # on how successful they've been so far?

    if @should_gridScan()
      return @gridScan

    if @should_thinkInsideTheBox()
      @record.push {type: "strat", strat: "ThinkInsideTheBox"}
      @prev_results.push {strat: "ThinkInsideTheBox",
                          num_set: 0, knowledge_gained: 0}
      log "Trying Think Inside the Box"
      return @thinkInsideTheBox

    if @should_smartGridScan()
      @record.push {type: "strat", strat: "SmartGridScan"}
      @prev_results.push {strat: "SmartGridScan",
                          num_set: 0, knowledge_gained: 0}
      log "Trying Smart Grid Scan"
      return @smartGridScan

    # FIXME
    # if @should_thinkOutsideTheBox()
    # if @should_exhaustionSearch()
    # if @should_desperationSearch()

  # Solves the grid and returns an array of steps used to animate those steps.
  solve: ->
    @record = []
    @strat_results = []
    iter = 1

    until @grid.is_solved() or @solve_iter > max_solve_iter
      strat = @choose_strategy()
      strat()

    log if @grid.is_solved() then "Grid solved! :)" else "Grid not solved :("

    dom.solve_done_animate()
































  ### Strategies ###

  #### Smart Grid Scan ####
  # Consider each value, in order of currently most present on the grid to least
  # present (as above, with the order pre-computed). For each value v, consider
  # each box b where v has not yet been filled in. Let p be the set of positions
  # where v can be placed within b. If p is a single position, then fill in v at
  # this position (note that this is extremely similar to GridScan in this
  # case). If all the positions in p are in a single row or col, then add a
  # restriction of v to all other cells in the row or col but outside of
  # b.
  #
  # NOTE: This is mostly a knowledge refinement strategy, and the goal is to
  # only add a couple restrictions here and there, which would then be picked up
  # by ExhaustionSearch, but we will also fill in some values which Grid Scan
  # would not pick up (since we will consider something more strict than naively
  # impossible values).
  #
  # FIXME: actually consider something mroe strict than naively impossible
  # vaules, and also completely restructure this: should only store restrictions
  # if a set of restrictions already exists, and something like Exhaustion
  # Search should instead create them initially.

  # Get the list of values in order of their occurrences, and start the main
  # value loop.
  SmartGridScan: ->
    log "Trying SmartGridScan"

    @updated = false

    vals = @vals_by_occurrences()

    @SmartGridValLoop(vals, 0)

  # For a specified value, get the boxes where that value has not yet been
  # filled in. If there are such boxes, then begin a box loop in the frsit of
  # the boxes; if there are no such boxes, then either go to the next value or
  # finish the strategy.
  SmartGridValLoop: (vs, vi) ->
    v = vs[vi]

    boxes = []
    # Get the boxes which don't contain v, which are the only ones we're
    # considering for this startegy.
    for b in [0..8]
      boxes.push(b) if v not in @grid.get_box_vals(b)

    # If there are possible boxes, then start iterating on them.
    if boxes.length > 0
      @SmartGridBoxLoop(vs, vi, boxes, 0)
    # If there are no more possible boxes, then move on to the next value or the
    # next strategy.
    else
      # If there are more values, move to the next value.
      if vi < vs.length - 1
        @SmartGridValLoop(vs, vi+1)
      # If there are no more values, move to the next strategy.
      else
        @prev_results[@prev_results.length-1].success = @updated
        setTimeout(( => @solve_loop()), STRAT_DELAY)

  # For a specified value and box, see where the values is possible in the
  # box. If the value is only possible in one position, then fill it in (like
  # normal GridScan). If it's possible in two or three positions, and those
  # positions happen to be in the same rows or cols, then will add restrictions
  # to all the other cells in the same row/col outside the box. Move on to the
  # next box if there are more boxes; move on to the next value if there are no
  # more boxes and there are more values; move on to the next strategy if there
  # are no more boxes or values.
  SmartGridBoxLoop: (vs, vi, bs, bi) ->
    v = vs[vi]
    b = bs[bi]

    ps = @naive_possible_positions_in_box v, b

    next_box = ( => @SmartGridBoxLoop(vs, vi, bs, bi+1) )
    next_val = ( => @SmartGridValLoop(vs, vi+1) )
    next_strat = ( => @solve_loop() )

    # Go to the next box if there are more boxes.
    if bi < bs.length - 1
      callback = next_box
      delay = 0
    # Go to the next value if there are no more boxes, but more values.
    else if vi < vs.length - 1
      callback = next_val
      delay = 0
    # Go to the next strategy if there are no more values or boxes.
    else
      callback = next_strat
      delay = STRAT_DELAY

    switch ps.length
      when 1
        log "Setting (#{util.base_to_cart ps[0]}) to #{v} by SmartGridScan"
        @set(ps[0], v, =>
          @updated = true
          delay += FILL_DELAY)
      when 2,3
        just_updated = false
        if @same_row(ps)
          y = @same_row(ps)
          for x in [0..8]
            i = util.cart_to_base(x,y)
            unless @grid.idx_in_box(i,b) or @grid.get(i) != 0
              just_updated = @add_restriction(i,v)
        else if @same_col(ps)
          x = @same_col(ps)
          for y in [0..8]
            i = util.cart_to_base(x,y)
            unless @grid.idx_in_box(i,b) or @grid.get(i) != 0
              just_updated = @add_restriction(i,v)
        log "Refining knowldege base using SmartGridScan" if just_updated
        @updated ||= just_updated

    setTimeout(callback, delay)

  # Heuristic for whether Smart Grid Scan should be performed.
  should_smartgridscan: ->
    # Should do a smart gridscan if the last attempt at gridscan failed. this
    # should work because gridscan is always run first, so there should always
    # be previous strategies with gridscan among them.
    last_gridscan = -1
    _.each(@prev_results, (result, i) ->
      last_gridscan = i if result.strat == "GridScan" )
    return not @prev_results[last_gridscan].success


  #### Think Inside the Box ####
  # For each box b and for each value v which has not yet been filled in within
  # b, see where v could possibly be placed within b (consulting th evalues in
  # corresponding rows/cols and any cant/must arrays filled in within b); if v
  # can only be placed in one position in b, then fill it in.

  # Get a list of boxes and begin the main loop through the box list.
  ThinkInsideTheBox: ->
    @updated = false

    boxes = [0..8]

    @ThinkInsideBoxLoop(boxes, 0)

  # Get the list of values which have not yet been filled in within the current
  # box, and begin a loop through those values.
  ThinkInsideBoxLoop: (bs, bi) ->
    filled = @grid.get_box_vals bs[bi]
    vals = _.without([1..9], filled...)

    # If there are unfilled values, then start iterating on them
    if vals.length > 0
      @ThinkInsideValLoop(bs, bi, vals, 0)
    else
      # If there are no unfilled values and there are more boxes to consider,
      # then move on to the next box.
      if bi < bs.length - 1
        @ThinkInsideBoxLoop(bs, bi+1)
      # If there are no unfilled values and there are no more boxes to consider,
      # then go to the next strategy.
      else
        @prev_results[@prev_results.length-1].success = @updated
        setTimeout(( => @solve_loop()), STRAT_DELAY)

  # See where the current value can be placed within the current box. If the
  # value is only possible in one position, then fill it in. Move on to the next
  # value if there are more values; move on to the next box if thre are no more
  # values and there are more boxes; move on to the next strategy if there are
  # no more values or boxes.
  ThinkInsideValLoop: (bs, bi, vs, vi) ->
    v = vs[vi]
    b = bs[bi]

    ps = @naive_possible_positions_in_box v, b

    next_val = ( => @ThinkInsideValLoop(bs, bi, vs, vi+1) )
    next_box = ( => @ThinkInsideBoxLoop(bs, bi+1) )
    next_strat = ( => @solve_loop() )

    # Go to the next value if there are more values.
    if vi < vs.length - 1
      callback = next_val
      delay = 0
    # Go to the next box if there are no more values, but more boxes.
    else if bi < bs.length - 1
      callback = next_box
      delay = 0
    # Go to the next strategy if there are no more boxes or values.
    else
      callback = next_strat
      delay = STRAT_DELAY

    if ps.length == 1
      log "Setting (#{util.base_to_cart ps[0]}) to #{v} by ThinkInsideTheBox"
      @set(ps[0], v, =>
        @updated = true
        delay += FILL_DELAY
        setTimeout(callback, delay))
    else
      if callback == next_strat
        @prev_results[@prev_results.length-1].success = @updated
      setTimeout(callback, delay)

  # Heuristic for whether Think Inside the Box should be peformed.
  should_thinkinsidethebox: ->
    # Do ThinkInsideTheBox unless the last attempt at ThinkInsideTheBox failed.
    last_thinkinside = -1
    _.each(@prev_results, (result, i) ->
      last_thinkinside = i if result.strat == "ThinkInsideTheBox" )
    return last_thinkinside == -1 or @prev_results[last_thinkinside].success



  ### Solve Loop ###

  # Choose a strategy, using the heuristic each strategy provides.
  # FIXME should provide a weighting system based on previous success/failure of
  # attempts at strategies.
  choose_strategy: ->
    if @should_gridscan()
      @prev_results.push {strat: "GridScan"}
      dom.announce_strategy "GridScan"
      log "Trying GridScan"
      return @GridScan()

    if @should_thinkinsidethebox()
      @prev_results.push {strat: "ThinkInsideTheBox"}
      dom.announce_strategy "ThinkInside<br />TheBox"
      log "Trying ThinkInsideTheBox"
      return @ThinkInsideTheBox()

    if @should_smartgridscan()
      @prev_results.push {strat: "SmartGridSCan"}
      dom.announce_strategy "SmartGridScan"
      log "Trying ThinkInsideTheBox"
      return @SmartGridScan()

    # FIXME

    # if @should_thinkoutsidethebox()
    #   return @ThinkOutsideTheBox()

    # if @should_exhaustionsearch()
    #   return @ExhaustionSearch()

    # if @should_desperationsearch()
    #   return @DesperationSearch()

  solve_loop: ->
    @solve_iter += 1
    log "iteration #{@solve_iter}"

    # Stop if the grid is complete or we've done too many iterations.
    done = @grid.is_solved() or @solve_iter > max_solve_iter

    if done
      @solve_loop_done()
    else
      @choose_strategy()


  solve_loop_done: ->
    log if @grid.is_solved() then "Grid solved! :)" else "Grid not solved :("

    dom.solve_done_animate()

  solve: ->
    @solve_loop()


## Wrap Up ##
# Export the Solver class to the window for access in the main file.
root.Solver = Solver