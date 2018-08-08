import dvar.DVar;
import dvar.DVarMacro.dep as dep;
import Test;

@:access(src.dvar.DVar)
class Main {
    public static function main():Void {

        var a = new DVar<Int>(0);
        var b = new DVar<Int>(1);
        var c = new DVar<Int>(2);

        a.set(0);
        b.set(5);
        c.set(10);

        Test.begin();

        // Basic tests
        Test.ce("a val 0", a.get(), 0);
        Test.ce("b val 5", b.get(), 5);
        Test.ce("c val 10", c.get(), 10);

        c.def(dep(function(){ return a.get() + b.get(); }));
        Test.ce("c get val", c.get(), 5);

        a.def(dep(function() { return 3; } ));
        b.def(dep(function() { return a.get(); }));

        Test.ce("c get val", c.get(), 6);

        a.def(dep(function() { return 4; } ));
        Test.ce("a change to c", c.get(), 8);

        // a->b,c b->d d->c c->e
        var d:DVar<Int> = new DVar<Int>(0);
        var e:DVar<Int> = new DVar<Int>(0);

        c.def(dep(function(){ return e.get(); } ));
        d.def(dep(function(){ return c.get(); } ));
        b.def(dep(function(){ return d.get(); } ));
        a.def(dep(function(){ return b.get() + c.get(); } ));

        e.set(10);
        Test.ce("a val", a.get(), 20);

        // Topological order
        // We guarantee that b will run before c, and that c will always be true
        // Prereq: within a function we can only update our own stream
        var a = new DVar<Int>(0);
        var b = new DVar<Int>(0);
        var c = new DVar<Bool>(false);

        c.def(dep(function(){ return b.get() > a.get(); } ));
        b.def(dep(function(){ return a.get()+1; } ));

        a.set(10);
        a.set(20);
        a.set(5);
        Test.ce("c order true", c.get(), true);

        var a = new DVar<Int>(0);
        var b = new DVar<Int>(0);
        var c = new DVar<Int>(0);

        var changes:String = "";

        var addToChanges = function(varName:String, data:{old:Dynamic, change:Dynamic}){
            if(changes != "") changes += ",";
            changes += varName+":"+data.old+"->"+data.change;
        }

        b.register(addToChanges.bind("b"));
        c.register(addToChanges.bind("c"));

        b.def(dep(function(){ return a.get() + 3; } ));
        c.def(dep(function(){ return b.get() + 4; } ));

        Test.ce("no changes ", changes, "");
        c.setForce(true);
        Test.ce("bc change ", changes, "b:0->3,c:0->7");
        changes = "";

        b.set(3); // ignore change, b and c
        Test.ce("no changes, same val ", changes, "");

        b.set(5); // do change
        Test.ce("prop change to c ", changes, "b:3->5,c:7->9");

        // setForce with def
        changes = "";
        // Test setForce on def
        var a = new DVar<Int>(0);
        var b = new DVar<Int>(0);
        b.def(dep(function(){ return a.get()+1; }));
        b.register(addToChanges.bind("b"));
        b.setForce(true);
        Test.ce("set force ",changes, "b:0->1");

        changes = "";
        a.def(dep(function(){ return 2; }));
        Test.ce("set force post def ",changes, "b:1->3");

        // Trying the defQueue
        var a = new DVar<Int>(0);
        var b = new DVar<Int>(0);

        changes = "";
        var i:Int = 1;
        b.def(dep(function(){ return a.get() + i; }));
        b.register(
            function(data){
                addToChanges("b", data);
                if(data.change < 5){
                    i++;
                    b.def(dep(function(){ return a.get() + i; }));
                }
            });
        b.setForce(true);
        Test.ce("queueDef b", changes, "b:0->1,b:1->2,b:2->3,b:3->4,b:4->5");

        // Trying the defQueue between
        var a = new DVar<Int>(0);
        var b = new DVar<Int>(0);
        var c = new DVar<Int>(0);

        changes = "";
        var i:Int = 1;
        var i:Int = 1;
        b.def(dep(function(){ return a.get() + i; }));
        c.def(dep(function(){ return b.get(); }));
        b.register(
            function(data){
                addToChanges("b", data);
                if(data.change < 5){
                    i++;
                    b.def(dep(function(){ return a.get() + i; }));
                }
            });
        c.register(addToChanges.bind("c"));
        c.setForce(true);

        Test.ce("queueDef b, c order", changes, 
            "b:0->1,c:0->1,b:1->2,c:1->2,b:2->3,c:2->3,b:3->4,c:3->4,b:4->5,c:4->5");

        // Test cap on defqueue updates; should throw an exception
        // if we are processing too many things.
        var caught:Bool = false;
        var a = new DVar<Int>(0);
        var i:Int = 1;
        a.def(dep(function(){ return i; }));
        a.register(
            function(data){
                //trace(data);
                i++;
                a.def(dep(function(){ return i; }));
            });
        try {
            a.setForce(true);
        } catch(e:Dynamic) {
            caught = true;
        }
        Test.ce("queueDef catch ", caught, true);

        // CYCLE TESTS
        var a = new DVar<Int>(0);
        a.def(dep(function(){ return a.get()+1; }));
        Test.ce("self cycle ", a.get(), 0);

        var a = new DVar<Int>(0);
        var b = new DVar<Int>(0);
        a.def(dep(function(){ return b.get()+1; }));
        b.def(dep(function(){ return a.get()+1; }));
        Test.ce("co-cycle b", b.get(), 0);
        Test.ce("co-cycle a", a.get(), 0);

        a.set(2);
        Test.ce("co-cycle break ", b.get(), 3);

        changes = "";
        var a = new DVar<Int>(0);
        b.set(0);
        b.def(dep(function(){ return a.get()+1; }));
        a.def(dep(function(){ return b.get()+1; }));
        b.setForce(true);

        b.register(addToChanges.bind("b"));
        Test.ce("no change during co-cycle ",changes, "");

        a.set(3);
        Test.ce("change on break co-cycle ",changes, "b:3->4");

        // BROADCAST QUEUE
        var a = new DVar<Int>(0);
        var b = new DVar<Int>(1);

        changes = "";

        var i:Int = 0;
        b.register(
            function(data){
                addToChanges("b", data);
                i++;
                if(i < 5){
                    a.set(i);
                }
                b.set(a.get());
            });
        b.set(a.get());
        b.setForce(true);
        Test.ce("broadcast order, updates within register", changes, 
            "b:1->0,b:0->1,b:1->2,b:2->3,b:3->4");

        // BROADCAST LAZY
        var a = new DVar<Int>(0);
        var b = new DVar<Int>(1);

        b.def(dep(
            function(){
                return a.get();
            }));

        changes = "";
        b.register(addToChanges.bind("b"));

        b.get();
        Test.ce("lazy register update", changes, "b:1->0");

        Test.end(true);
    }
}
