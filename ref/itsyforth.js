// (completely untested) javascript port of itsyforth's outer interpreter
// http://www.retroprogramming.com/2012/03/itsy-forth-1k-tiny-compiler.html

function module_itsy( export ) {

  var type = { NORMAL : -1, IMMEDIATE : 1 }

  function Entry(addr) {
    this.word = "";
    this.cfa  = addr + 1;
    this.dfa  = addr + 1;
    this.type = types.NORMAL;
  }

  var 
    ram = new Int32Array( 65536 ),
    tib = "",	     // text input buffer
    inp = 0,         // offset into tib ( >in in forth )
    data = [],       // data stack
    dict = [],       // dictionary
    state = 0,       // 0=compile 1=execute
    here  = 0,       // write pointer (offset into ram)
    tmpStrAdr = 128, // temp string address
    base = 10,
    digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";


  // store a string inside the vm
  function store( str, adr ) {
    ram[ adr++ ] = str.length;
    for ( var i = 0; i < str.length; ++i ) {
      ram[ adr++ ] = str.charCodeAt( i );
    }
  }

  // fetch the next word from the input buffer, returning its address
  // http://lars.nocrew.org/dpans/dpans6.htm#6.1.2450
  function WORD( ) {
    var end = tib.indexOf( String.fromCharCode( data.pop()), inp );
    if (-1 == end) store( "", tmpStrAdr ) 
    else store( tib.substring( inp, end ), tmpStrAdr );
  }
  
  // look the word up in the current scope, leaving also flag =1 for found
  function FIND() {
    var wd = data.pop(), found = false;
    for (var i = dict.length-1; i >= 0 && !found; i--) {
      if (dict[i] == wd) {
        data.push( i );
        data.push( if dict[i].is_immediate ? 1 : -1 );
	found = true;
      }
    }
    if (!found) data.push( 0 );
  }

  // duplicate top item on the stack    
  function DUP() {
    data.push( data( data.length-1 ));
  }

  // write a value to ram. this is "," (comma) in forth
  function COMPILE() {
    ram[ here++ ] = data.pop();
  }

  // execute the address on the stack
  function EXECUTE() {
    data.drop();
    console.log("TODO");
  }

  // rotate ( a b c -- b c a )
  function ROT(){ 
     var c = data.pop(),
         b = data.pop(),
	 a = data.pop();
     data.push( b );
     data.push( c );
     data.push( a );
  }

  // http://lars.nocrew.org/dpans/dpans6.htm#6.1.0980
  // ( strAdr -- @str[0] str.length )
  function COUNT() {
    var adr = data.pop();
    data.push( adr + 1 );  // address of the first character
    data.push(ram[ adr ]); // length of the string
  }
  
  // http://lars.nocrew.org/dpans/dpans6.htm#6.1.0570
  // ( init c-adr len -- result end-adr bad )
  function TONUMBER() {
    var len = data.pop(),
        adr = data.pop(),
	res = data.pop(),
	err = false;
    for (var i = len; i >= 0 && !err; --i) {
      var ch  = ram[ adr++ ],
          val = digits.indexOf( ch );
      if ( val < base && val >= 0 ) { // -1 would mean not found
        res *= base;
	res += val;
      }
      else err = true;
    }
    data.push( res );
    data.push( adr );
    data.push( i+1 );
  }

  // interpreter routine.  
  export.interpret = function( ) {
    if (inp == tib.length) {
      tib = get_input();
      inp = 0;
    }
    data.push( 32 ); WORD(); FIND(); DUP();
    if (data.pop()) { // word found? stack = [ ..., word_addr, (1 or -1) ]
      if (data.pop() == state) {
        state ? COMPILE() : EXECUTE();
      }
    }
    else { // word not found. stack = [ addr of input, 0 ]
      DUP();      // [ adr, 0, 0 ]
      ROT();      // [ 0, 0, adr ]
      COUNT();    // [ 0, 0, str[0], len ]
      TONUMBER(); // [ 0, 0, int, adr, bad ]
      if (data.pop()) {
        // bad != 0, so conversion to a number failed.
        if (state) {
	  // TODO: abandon_definition_in_progress;
	  // retroforth doesn't do this. it just keeps compiling.
	  // itsyforth: last @ dup @ last ! dp !
	  return
	} else {
          data.pop(); data.pop();
          if (state) {
	    COMPILE( vm.LIT );
	    COMPILE( data.pop());
          }
        }
      }
    }
  }
}

/* -- junk i wound up not needing ---
  function IFSO() { return data.pop(); }
  function THEN() { }
  function ELSE() { }
  var t, n;
  function poptn() { t = data.pop(), n = data.pop() };

  // forth '@'
  function GET() { data.push(ram[ data.pop( )]); } 
  
  // forth '!'
  function PUT() { poptn(); ram[ t ] = n; }

*/