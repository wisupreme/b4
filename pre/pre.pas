{ -----------------------------------------------------------------

  pre : a pattern recognition engine

  copyright (c) 2012 michal j wallace
  see ../LICENSE.org for ( MIT-style ) licensing details

---------------------------------------------------------------- }
{$i xpc.inc }
unit pre;
interface uses xpc, stacks, ll, ascii, num;

  type

    Marker  = class end;
    MarkerStack = specialize Stack< Marker >;

    Source = class
      procedure next( var ch : char );   virtual; abstract;
      procedure mark( var mk : Marker ); virtual; abstract;
      procedure back( var mk : Marker ); virtual; abstract;
      function consumed : string; virtual; abstract;
    end;

    StringSource = class ( Source )
      constructor create( s : string );
      procedure next( var ch : char );   override;
      procedure mark( var mk : Marker ); override;
      procedure back( var mk : Marker ); override;
      function consumed : string; override;
    private
      idx : word;
      str : string;
    end;

    Token = class
      sym, pos, len : cardinal;
    end;

    CharSet = set of Char;
    matcher = class; // forward reference

    Pattern = class
      function match( m : matcher )  : boolean; virtual; abstract;
      function matches( s : string ) : boolean; virtual; abstract;
    end;

    patterns = array of pattern;

    { match effects ( for DefPattern )
      ----------------------------------
      The =match_effect= type specifies what to do after successfully
      matching a named pattern created with the 'def' constructor. }

    match_effect = (
      ef_fragment, // do nothing. intended for e.g. 'alpha' / 'digit'
      ef_token,    // emit a token containing the matched text.
      ef_enlist,   // create a new node to wrap the child tokens
      ef_stream,   // append child tokens to current node ( no new wrapper )
      ef_hidden    // emits a 'hidden' token for comments, whitespace, etc.
    );

    { matcher contains the hand-written methods that
      actually carry out the work of matching things. }
    matcher = class

      { pattern constructors -  +*+*+ magic stuff happens here! +*+*
        ------------------------------------------------------------
        This section of the matcher interface is parsed by pre_gen.py,
        which generates module-level functions with the same names and
        arguments, except they return pattern objects rather than booleans.

        That script /also/ generates a new class corresponding to each
        method, capable of holding the arguments as a data structure.

        For example, the definition of =matcher.sym= here triggers the
        generation of code for a class called =SymPattern= ( a subclass
        of =Pattern=, as well as a =function sym( const c : char ) : Pattern=
        at the module level that invokes =SymPattern='s constructor and
        returns the result. }
    protected

      { primitive : character classes }
      function nul : boolean;
      function sym( const c  : char ) : boolean;
      function any( const cs : charset ) : boolean;
      function lit( const s  : string) : boolean;

      { regular expression support }
      function opt( p : pattern ) : boolean;   // like regexp '?'
      function rep( p : pattern ) : boolean;   // like '*'
      function alt( const ps : patterns ) : boolean; // like "|"
      function seq( const ps : patterns ) : boolean; // like "(...)"

      { recursion support, for context-free grammars }
      function sub( const iden : string ) : boolean;


    { public interface for matcher class itself }
    public
      constructor create;
      constructor create( s : string );
      procedure match( s : source; rule: string );
      function consumed : string;

    { matcher internal state }
    private
      src   : Source;
      ch    : Char;
      marks : MarkerStack;
      point : int32;

      { state management routines }
      procedure next;
      procedure mark;
      procedure back;
      procedure keep;

    end;


  {-- module-level routines -----------------------}

  procedure def( const iden : string; p : pattern;
                   effect : match_effect = ef_stream );

  { support for multiple grammars }
  procedure new_grammar( const iden : string );
  procedure end_grammar;
  procedure use_grammar( const iden : string );

  {$i pre.intf.inc }  // generated by pre_gen.py

  { helper routines : only  for bootstrapping and testing }
  function ps( len : cardinal ) : patterns; { creates a new patterns array }
  procedure p( pat : pattern ); { appends to the last array }

implementation

  {$i pre.impl.inc }  // generated by pre_gen.py

  type pattern_def = record
		       iden : string;
		       p    : Pattern;
		       ef   : match_effect
		     end;
  var defs : array of pattern_def;

  {  ( TODO ) : support for multiple grammars }
  procedure new_grammar( const iden : string ); begin end;
  procedure end_grammar; begin end;
  procedure use_grammar( const iden : string ); begin end;

  {-- matcher : public interface --}

  constructor matcher.create;
  begin self.create( '' );
  end;

  constructor matcher.create( s	: string );
  begin
    self.src := StringSource.create( s );
    self.marks.init( 32 );
  end;

  procedure matcher.match( s : source; rule : string );
  begin
    self.src := s;
    self.sub( rule )
  end;

  function matcher.consumed : string;
  begin result := self.src.consumed;
  end;


  {-- matcher : primitive recognizers -----------}

  { nul : always matches, without consuming any characters }
  function matcher.nul : boolean;
  begin
    result := true;
  end;

  { sym : tests equality with a specific symbol }
  function matcher.sym( const c : char ) : boolean;
  begin
    mark; next;
    result := self.ch = c;
    if result then keep else back;
  end;

  { any : tests membership in a set of characters }
  function matcher.any( const cs : charset ) : boolean;
  begin
    mark; next;
    result := self.ch in cs;
    if result then keep else back;
  end;

  { lit : tests equality with a specific symbol }
  function matcher.lit( const s : string ) : boolean;
    var i : word;
  begin
    mark;
    result := true;
    for i := 1 to length( s ) do begin
      next;
      if self.ch <> s[ i ] then result := false;
    end;
    if result then keep else back;
  end;

  {-- matcher : pattern combinators -------------}

  { seq : ( sequence ) simply matches each pattern from left to right.
    it succeeds if and only if each pattern in the sequence succeeds. }
  function matcher.seq( const ps : patterns ) : boolean;
    var i : integer;
  begin
    mark;
    i := low( ps ); result := true;
    repeat
      result := result and ps[ i ].match( self );
      inc( i )
    until ( i > high( ps )) or not result;
    if result then keep else back;
  end;

  { alt : can match any one of the given patterns }
  // !! NOTE: in this implementation, the first match wins, so it acts
  //    like a parsing expression grammar. Most of the languages I'm
  //    parsing are LL(1), so I don't think this actually makes any
  //    difference.
  function matcher.alt( const ps : patterns ) : boolean;
    var i : integer = 0 ; found : boolean = false;
  begin
    repeat
      mark;
      found := ps[ i ].match( self );
      inc( i );
      if found then keep else back;
    until found or ( i > high( ps ));
    result := found;
  end;

  { opt : ( optional ) tries to match a pattern,
    but if the pattern doesn't match, it backtracks
    and returns true anyway.
    algebraically, opt p = alt ( p , nul ) }
  function matcher.opt( p : pattern ) : boolean;
  begin
    mark;
    if p.match( self ) then keep else back;
    result := true;
  end;

  { rep : ( repeating ) is like opt, but it will keep consuming
    input until the underlying pattern fails. since matching 0
    copies is still a match, rep always succeeds }
  function matcher.rep( p : pattern ) : boolean;
  begin
    repeat
      mark;
      result := p.match( self );
      if result then keep else back;
    until not result;
    result := true;
  end;

  {--  dictionary routines ----------------------}

  { def : assigns a name to the specified pattern. }
  procedure def( const iden : string ; p : pattern;
                 effect : match_effect = ef_stream );
    var len : cardinal;
  begin
    len := length( defs );
    setlength( defs, len + 1 );
    defs[ len ].iden := iden;
    defs[ len ].p := p;
    defs[ len ].ef := effect;
  end;

  { lookup : searches through the dictionary backward, so that the last
    entry added is the one returned }
  function lookup(const iden   : string;
		    var p      : pattern;
		    var effect : match_effect ) : boolean;
    var i : integer; found : boolean = false;
  begin
    i := high( defs );
    while not found and ( i >= low( defs )) do
    begin
      found := defs[ i ].iden = iden;
      if found then p := defs[ i ].p;
      dec( i )
    end;
    result := found;
  end;

  {-- matcher : named rules ---------------------}
  { this one is pretty much the core concept behind the parse engine. }

  { sub : invokes a rule ( provided it's found in the dictionary ) }
  function matcher.sub( const iden : string ) : boolean;
    var p : pattern; effect : match_effect;
  begin
    if lookup( iden, p, effect ) then begin
      self.mark;
      result := p.match( self );
      //  TODO : build the tree
      if result then case effect of
	ef_fragment : pass;
	ef_token    : pass;
	ef_enlist   : pass;
	ef_stream   : pass;
	ef_hidden   : pass;
      end
      else self.back
    end
    else die( 'couldn''t find sub: ' + iden )
  end;


  {-- matcher : state management ----------------}

  procedure matcher.next;
  begin
    self.src.next( self.ch )
  end;

  procedure matcher.mark;
    var mk : marker;
  begin
    self.src.mark( mk );
    self.marks.push( mk );
  end;

  procedure matcher.keep;
  begin
    self.marks.pop;
  end;

  procedure matcher.back;
    var mk : marker;
  begin
    mk := self.marks.pop;
    self.src.back( mk )
  end;


  {-- strings as input sources ------------------}

  { Why make explicit objects for string sources instead of just using
    strings?  Strings are the most common case ( which is why the
    interface hides all this from the user -- see test_pre.pas for
    example usage ), but I would like to pattern match on all kinds of
    things. Some examples:

      - DOM elements for validating XML
      - argument types ( for type-checking inside a compiler )
      - spatial movements for mouse gestures or handwriting recognition.

    Regular expressions and grammars can be applied to recognize all
    of these things, and this extra overhead is what allows it to
    happen.

    <Granted, this is somewhat premature, and the matcher interface
    will have to be updated to use generic types rather than just
    chars before this can actually be applied.> }

  constructor StringSource.create( s : string );
  begin
    self.idx := 0;
    self.str := s;
  end;

  { This same concept explains StringMarker. To mark a position in a
    string, you just use an offset. So why not just an int? Because if
    we're matching trees or graphs we'd need a path rather than a
    simple number.

    Note also that =StringMarker= is not exposed in the interface
    section, so it's private. Outside callers only know that they're
    getting a =Marker=, but they don't have any way to inspect or
    interfere with it. This makes =Marker= an abstract data type. }

  type StringMarker = class( Marker )
    idx : word
  end;

  {-- StringSource implementation --}

  procedure StringSource.next( var ch : char );
  begin
    if self.idx = length( self.str ) then ch := ascii.EOT
    else begin
      inc( self.idx );
      // writeln(' idx:', self.idx, '  str:', self.str  );
      ch := self.str[ self.idx ];
    end;
  end;

  procedure StringSource.mark( var mk : Marker );
  begin
    mk := StringMarker.create;
    ( mk as stringmarker ).idx := self.idx;
  end;

  procedure StringSource.back( var mk : Marker );
  begin
    assert( mk is stringmarker );
    self.idx := ( mk as stringmarker ).idx;
  end;

  function StringSource.consumed : string;
  begin
    result := copy( self.str, 1, self.idx );
  end;

  {-- tools to create the meta-parser ------------}

  { The idea is that besides using the constructors and combinators
    in straight pascal, you should also be able to specify your
    language in terms of an EBNF-style grammar.

    But, in order to make that happen, we've got to write a parser
    for the grammar language, and that's what the rest of the code
    in this file does.

    Unforutanely, the pascal/delphi syntax isn't quite expressive
    enough to do this cleanly, and so we're first going to define
    two small "builder" routines to help us out:
  }

  // given the grammar rule:
  //
  //    expr = term  { "|" term } .
  //
  //  I want to say:
  //
  //    def( 'expr',
  //         seq([ sub( 'term' ), rep([ lit( '|' ), sub( 'term' )])]));
  //
  // unfortunately, as far as i can tell, there's no way to express a
  // literal dynamic array like this. ( if there is, i'd love to hear
  // hear about it. )
  //
  // in the meantime, i made the following two builder functions.
  // their only purpose is to make the ebnf grammar easier to read.

  var
    build     : patterns;
    build_max : integer = 0;
    build_idx : integer = 0;


  { ps( len ) : creates a new pattern array with =len= elements }
  // !! I added the 'len' parameter because calling setlength
  //    actually creates a new copy of the array. Normally this
  //    is fine, but when you have multiple pointers pointing
  //    at the array, the other pointers still point to the
  //    original. A better option might be to wrap the array
  //    in a class, but for the moment, these routines are
  //    really only used for testing pre and bootstrapping
  //    the ebnf grammar parser, so it's not really worth it.
  function ps( len : cardinal ): patterns;
  begin
    if build_max <> build_idx then
      die( 'expected ' + n2s( build_max ) +
	  ' patterns, got ' + n2s( build_idx + 1 ))
    else begin
      setlength( build, len ); // setlength makes a new copy
      result := build;
      build_max := len;
      build_idx := 0;
    end
  end;

  { p( pat ) : fills the next open slot in the array created by ps }
  procedure p( pat : pattern );
  begin
    build[ build_idx ] := pat;
    inc( build_idx );
  end;

initialization

  {-- Parser for the EBNF meta-grammar ----------}

  // Here, we hand-build the bootstrap parser for ebnf grammars.
  // This uses the simplified pattern constructors from the generated
  // include file, combined with our two builder functions.
  //
  // The comments for each rule show the EBNF grammar rule we
  // /would/ type to create the same definition, if we'd already
  // had an EBNF parser.

  new_grammar( 'ebnf' );

  // grammar = { rule } .
  // --------------------
  def( 'grammar', rep( sub( 'rule' )), ef_enlist );

  // rule = iden "=" expr .
  // ----------------------
  def( 'rule', seq( ps( 4 )), ef_enlist );
    p( sub( 'iden' ));
    p( lit( '=' ));
    p( sub( 'expr' ));
    p( lit( '.' ));

  // iden = alpha { alpha | digit } .
  // --------------------------------
  // !! this one has a sub-rule inside a seq.
  //    I broke it into two parts rather than
  //    complicate the builder framework further
  def( 'iden', seq( ps( 2 )), ef_token );
    p( sub( 'alpha' ));
    p( sub( 'iden-tail' ));
  def( 'iden-tail', rep( alt( ps( 2 ))), ef_fragment );
    p( sub( 'alpha' ));
    p( sub( 'digit' ));

  // alpha = 'a' | ... | 'z' | 'A' | ... | 'Z'
  // -----------------------------------------
  def( 'alpha',   any([ 'a'..'z', 'A'..'Z' ]), ef_fragment );

  // digit = '0' | ... | '9'
  // -----------------------
  def( 'digit',   any([ '0'..'9' ]), ef_fragment );


  // expr = term  { "|" term } .
  // ---------------------------
  def( 'expr', seq( ps( 2 )), ef_enlist );
    p( sub( 'term' ));
    p( sub( 'expr-tail' ));
  def( 'expr-tail', rep( seq( ps( 2 ))), ef_stream );
    p( lit( '|' ));
    p( sub( 'term' ));

  // term = { factor } .
  // -------------------
  def( 'term', rep( sub( 'factor' )), ef_stream );

  // rep = "{" expr "}" .
  // --------------------
  def( '{rep}', seq( ps( 3 )), ef_enlist );
    p( lit( '(' ));
    p( sub( 'expr' ));
    p( lit( ')' ));

  // opt = "[" expr "]" .
  // --------------------
  def( '[opt]', seq( ps( 3 )), ef_enlist );
    p( lit( '[' ));
    p( sub( 'expr' ));
    p( lit( ']' ));

  // grp = "(" expr ")" .
  // --------------------
  def( '(grp)', seq( ps( 3 )), ef_enlist );
    p( lit( '(' ));
    p( sub( 'expr' ));
    p( lit( ')' ));


  // factor = iden | string | rep | opt | grp .
  // ------------------------------------------
  def( 'factor', alt( ps( 5 )), ef_stream );
    p( sub( 'iden' ));
    p( sub( 'string' ));
    p( sub( '{rep}' ));
    p( sub( '[opt]' ));
    p( sub( '(grp)' ));

  // str = """ { str-esc | any other character } """ .
  // -----------------------------------------------------
  def( 'str', seq( ps( 3 )), ef_token );
    p( lit( '"' ));
    p( sub( 'str-esc' ));
    p( lit( '"' ));

  // esc = "" ( "" | """ ) .
  // -------------------------------
  // Note : I use the ascii escape character as an escape character.
  // That is its purpose. :)
  //
  // If you can't see it in the line above, please consider filing
  // a bug report with whoever makes the tool you're using.
  //
  def( 'str-esc', alt( ps( 2 )), ef_fragment );
    p( sub( 'escaped' ));
    p( any([ #0 .. #255 ] - [ '"', #27 ])); // for sets, "-" means 'exclude'
  def( 'escaped', seq( ps( 2 )), ef_fragment );
    p( lit( #27 ));
    p( any([ #0 .. #255 ]));

  end_grammar;
end.
