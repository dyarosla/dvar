package dvar;

typedef Diff<T> = {old:T, change:T};

@:access(dvar.DVar)
class DStatic {
    public static var propQueue:List<DVar<Dynamic>> = new List();

    public static var defQueue:List<Void->Void> = new List();
    public static var dCount:Int = 0;
    public static var dCap:Int = 1000;

    public static var broadcastQueue:List<Void->Void> = new List();
    public static var bCount:Int = 0;
    public static var bCap:Int = 1000;
    public static var broadcasting:Bool = false;
    public static var processing:Bool = false;

    public static var cycleVars:List<DVar<Dynamic>> = new List();

    public static function clearCycles():Void {
        for(dvar in cycleVars){
            dvar.marked = false;
        }
        cycleVars.clear();
    }

    static function clearQueues():Void {
        broadcasting = false;
        processing = false;
        defQueue.clear();
        dCount = 0;
        broadcastQueue.clear();
        bCount = 0;
    }

    public static function process():Void {
        if(processing) return;
        processing = true;
        while(true){
            if(!propQueue.isEmpty()){
                propQueue.pop().get();
            } else if(!defQueue.isEmpty()){
                dCount++;
                if(dCount > dCap){
                    clearQueues();
                    throw "defQueue executed over max setting "+dCap;
                }
                var nextDef = defQueue.pop();
                nextDef();
            } else {
                break;
            }
        }
        processing = false;
        doBroadcast();
    }

    public static function doBroadcast():Void {
        while(true){
            if(broadcasting) return;
            if(!broadcastQueue.isEmpty()){
                broadcasting = true;
                bCount++;
                if(bCount > bCap){
                    clearQueues();
                    throw "broadcastQueue executed over max setting "+bCap;
                }
                var broadcast = broadcastQueue.pop();
                broadcast();
                broadcasting = false;
            } else {
                dCount = 0;
                bCount = 0;
                return;
            }
        }
    }
}

class DVar<T> {

    var val:T;
    var dirty:Bool;
    var force:Bool;
    var func:Void->T;
    var deps:Array<DVar<Dynamic>>;
    var listeners:Array<DVar<Dynamic>>;

    var marked:Bool = false;
    var cycle:Bool = false;

    var observers:Array<Diff<T>->Void>;
    var cycleObservers:Array<Bool->Void>;
    var eq:T->T->Bool;

    public function new(t:T, eq:T->T->Bool = null):Void {
        listeners = null;
        observers = null;
        deps = null;
        if(eq == null){
            this.eq = eqDefault;
        } else {
            this.eq = eq;
        }
        val = t;
        func = function(){ return t; };
        dirty = false;
    }

    // Update my value to t
    function updateVal(t:T):Void {
        dirty = false;
        if(eq(val, t)) return;
        if(observers == null){
            val = t;
        } else {
            var prev = val;
            val = t;
            updateObservers({old:prev, change:val});
            DStatic.process();
        }
    }

    // Set a value to t
    public function set(t:T):Void {
        def({func:function(){ return t; }, deps:null});
    }

    // If you want to change definitions within a register callback,
    // to ensure atomicity, you have to propQueue the definition
    public function def(data:{func:Void->T, deps:Array<DVar<Dynamic>>}):Void {
        DStatic.defQueue.add(defFunc.bind(data.func, data.deps));
        DStatic.process();
    }

    function defFunc(func:Void->T, deps:Array<DVar<Dynamic>> = null):Void {
        if(func == null){
            set(val);
            return;
        }

        this.func = func;
        clearDeps();

        this.deps = deps;
        if(deps != null){
            for(dep in deps){
                if(dep.listeners == null) dep.listeners = [];
                dep.listeners.push(this);
            }
        }

        invalidate();
        DStatic.clearCycles();
        DStatic.process();
    }

    public function setForce(f:Bool):Void {
        if(force == f) return;
        force = f;
        if(force && dirty){
            DStatic.propQueue.add(this);
            DStatic.process();
        }
    }

    public function get():T {
        if(!dirty && !cycle) return val;

        var startCycle = cycle;

        if(!marked){
            cycle = false;
            marked = true;
            dirty = true;
        } else if(!cycle){
            DStatic.cycleVars.add(this);
            cycle = true;
            if(deps != null){
                for(dep in deps){
                    dep.get();
                }
            }
            dirty = false;
            return val;
        } else {
            dirty = false;
            return val;
        }

        if(deps != null){
            for(dep in deps){
                dep.get();
            }
        }

        if(cycle){
            if(!startCycle){
                updateCycleObservers();
            }
            return val;
        }

        if(startCycle){
            updateCycleObservers();
        }

        marked = false;
        updateVal(func());

        return val;
    }

    public function getCache():T {
        return val;
    }

    function invalidateChildren():Void {
        if(listeners == null) return;
        for(listener in listeners){
            listener.invalidate();
        }
    }

    function invalidate():Void {
        if(dirty) return;
        if(force) DStatic.propQueue.add(this);
        dirty = true;
        invalidateChildren();
    }

    inline function clearDeps():Void {
        if(deps == null) return;
        for(dep in deps){
            dep.listeners.remove(this);
        }
        deps = null;
    }

    public function register(func:Diff<T>->Void, setForceTrue:Bool = false):Void {
        if(observers == null){
            observers = [func];
        } else {
            observers.push(func);
        }
        if(setForceTrue) setForce(true);
    }

    public function unregister(func:Diff<T>->Void):Void {
        if(observers == null) return;
        observers.remove(func);
        if(observers.length == 0) observers = null;
    }

    public function registerCycleObserver(func:Bool->Void):Void {
        if(cycleObservers == null){
            cycleObservers = [func];
        } else {
            cycleObservers.push(func);
        }
    }

    public function unregisterCycleObserver(func:Bool->Void):Void {
        if(cycleObservers == null) return;
        cycleObservers.remove(func);
        if(cycleObservers.length == 0) cycleObservers = null;
    }

    public function unregisterAll():Void {
        observers = null;
    }

    inline function updateObservers(diff:Diff<T>):Void {
        for(observer in observers){
            DStatic.broadcastQueue.add(observer.bind(diff));
        }
    }

    inline function updateCycleObservers():Void {
        if(cycleObservers == null) return;
        for(cycleObserver in cycleObservers){
            DStatic.broadcastQueue.add(cycleObserver.bind(cycle));
        }
    }

    public function isDirty():Bool { return dirty; }
    public function isCycle():Bool { if(dirty) get(); return cycle; }

    public function dispose():Void {
        clearDeps();
        observers = null;
        cycleObservers = null;
        listeners = null;
        eq = null;
        func = null;
    }

    static var eqDefault = function(t0:T, t1:T){ return t0 == t1; }
}
