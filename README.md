## DVar

Dependency variables with atomic updates, cycle handling, and observers.

### To Use

DVar is a variable whose value can be defined in terms of other variables.

To use it, import the following into your file:

```haxe
import dvar.DVar;
import dvar.DVarMacro.dep as dep;
```

Then create DVars and relationships like so:

```haxe
var a:DVar<Int> = new DVar(1);
a.get(); // 1

var b:DVar<Int> = new DVar(2);
b.get(); // 2

b.def(dep( function(){ return a.get() + 3; } )); // assign b to a + 3
b.get(); // 4
```

### Features

####Lazy Evaluation

DVars are lazy-evaluated.

```haxe
for(i in 0...1000){
	a.set(i);
}

// Changes to b have not been propogated
// When we call b.get(), we will unroll its dependencies.
b.get(); // 1003
```

####Register Observers to Changes

We can track changes to DVars with an observer function.

```haxe
b.register(
	function(data){
		trace("old:"+data.old+" -> new:"+data.change);
	});

a.set(10);

// Observer not called yet, as b is lazy-evaluated

b.get(); // observer called, tracing old:1003 -> new:13
```

####Force Non-Lazy Evaluation

Sometimes we want to track changes to a value at any point at which
the value could have changed. This requires us to forego lazy-evaluation
for those values.

Luckily, DVars can be forced to be non-lazy. Simply set

```haxe
b.setForce(true);
```

Used in conjunction with a `register` call,

```haxe
for(i in 0...1000){
	a.set(i); // will propogate to update b's value every time a is set,
			  // and will call any observers on b
}
```

####Atomic Updates

DVars propogate in a topologically sorted order. IE, if we have any form of
diamond in our dependency graph, and a value changes, every dependent value will
only be updated once, in the correct order.

Below, we create a dependency graph like this

```haxe
     a
   /   \
  b     c
   \   /
     d
```

```haxe
a.set(1);
b.def(dep(function(){ return a.get() + 1; }));
c.def(dep(function(){ return a.get() + 2; }));
d.def(dep(function(){ return b.get() + c.get(); }));

d.get(); // a <- 1, b <- 2, c <- 3, d <- 5
```

## Running the Tests

To run the tests, `cd` into `test` and compile using:

`haxe Test.hxml`

Then run tests using:

`out/cpp/main/Main-debug`
