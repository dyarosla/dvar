package dvar;

enum DStage {
    IDLE;
    MARK;
    PROP;
}

class DStatic {
    public static var queue:Array<DVar<Dynamic>> = [];
    public static var stage:DStage = IDLE;
    public static var defQueue:Array<{dvar:DVar<Dynamic>,
                                      data:{
                                          func:Void->Dynamic,
                                          ?deps:Array<DVar<Dynamic>>
                                         }}> = [];
    public static var nCount:Int = 0;
    public static var nCap:Int = 1000;
    public static var cycleVars:Array<DVar<Dynamic>> = [];
}

typedef Diff<T> = {old:T, change:T};

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
        }
    }

    function clearCycles():Void {
        for(dvar in DStatic.cycleVars){
            dvar.marked = false;
            dvar.cycle = false;
        }
        DStatic.cycleVars.splice(0, DStatic.cycleVars.length);
    }

    // Propogate updates to force-vars
    function propogate():Void {
        DStatic.stage = PROP;
        var len = DStatic.queue.length;
        for(i in 0...len){
            DStatic.queue[i].get();
        }
        DStatic.queue.splice(0, len);
        DStatic.stage = IDLE;
        processDefQueue();
    }

    // Set a value to t
    public function set(t:T):Void {
        def({func:function(){ return t; }, deps:null});
    }

    public function def(data:{func:Void->T, deps:Array<DVar<Dynamic>>}):Void {
        queueDef(this, data);
    }

    // If you want to change definitions within a register callback,
    // to ensure atomicity, you have to queue the definition
    // which will be executed as soon as DStage is IDLE
    function queueDef(dvar:DVar<Dynamic>,
                      data: {
                             func:Void->Dynamic,
                             ?deps:Array<DVar<Dynamic>>
                           }){
        DStatic.defQueue.push({dvar:dvar, data:data});
        if(DStatic.stage == IDLE){
            processDefQueue();
        }
    }

    function processDefQueue():Void {
        if(DStatic.defQueue.length == 0) {
            DStatic.nCount = 0;
            return;
        }

        DStatic.nCount++;
        if(DStatic.nCount > DStatic.nCap){
            DStatic.defQueue.splice(0, DStatic.defQueue.length);
            DStatic.nCount = 0;
            throw "defQueue executed over max setting "+DStatic.nCap;
        }

        var nextDef = DStatic.defQueue.shift();
        var dvar = nextDef.dvar;
        var data = nextDef.data;
        dvar.defFunc(data.func, data.deps);
    }

    function defFunc(func:Void->T, deps:Array<DVar<Dynamic>> = null):Void {
        DStatic.stage = MARK;
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
        clearCycles();
        propogate();
    }

    public function setForce(f:Bool):Void {
        force = f;
        if(force && dirty){
            DStatic.queue.push(this);
            propogate();
        }
    }

    public function get():T {
        if(!dirty) return val;

        if(!marked){
            marked = true;
        } else if(!cycle){
            DStatic.cycleVars.push(this);
            cycle = true;
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
            dirty = false;
            return val;
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
        if(force) DStatic.queue.push(this);
        dirty = true;
        invalidateChildren();
    }

    function clearDeps():Void {
        if(deps == null) return;
        for(dep in deps){
            dep.listeners.remove(this);
        }
        deps = null;
    }

    public function getIsDirty():Bool { return dirty; }

    public function register(func:Diff<T>->Void):Void {
        if(observers == null){
            observers = [func];
        } else {
            observers.push(func);
        }
    }

    public function unregister(func:Diff<T>->Void):Void {
        if(observers == null) return;
        observers.remove(func);
        if(observers.length == 0) observers = null;
    }

    public function unregisterAll():Void {
        observers = null;
    }

    function updateObservers(diff:Diff<T>):Void {
        for(observer in observers){
            observer(diff);
        }
    }

    static var eqDefault = function(t0:T, t1:T){ return t0 == t1; }
}
