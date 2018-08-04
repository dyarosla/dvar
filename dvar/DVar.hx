package dvar;

enum DepStage {
    IDLE;
    MARK;
    PROP;
}

class DepQueue {
    public static var queue:Array<DVar<Dynamic>> = [];
    public static var stage:DepStage = IDLE;
    public static var defQueue:Array<{dvar:DVar<Dynamic>,
                                      data:{
                                          func:Void->Dynamic,
                                          ?deps:Array<DVar<Dynamic>>
                                         }}> = [];
    public static var nCount:Int = 0;
    public static var nCap:Int = 1000;
    public static var cycleVars:Array<DVar<Dynamic>> = [];
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

    var observers:Array<{old:T, change:T}->Void>;
    var eq:T->T->Bool;

    public function new(t:T, eq:T->T->Bool = null):Void {
        listeners = null;
        observers = null;
        deps = null;
        if(eq == null){
            this.eq = function(t0, t1){ return t0 == t1; }
        } else {
            this.eq = eq;
        }
        func = null;
        val = t;
        dirty = false;
    }

    // Update my value to t
    function updateVal(t:T):Void {
        // we need to mark clean independent of if our value changed
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
        for(dvar in DepQueue.cycleVars){
            dvar.marked = false;
            dvar.cycle = false;
        }
        DepQueue.cycleVars.splice(0, DepQueue.cycleVars.length);
    }

    // Propogate updates to force-vars
    function propogate():Void {
        DepQueue.stage = PROP;
        var len = DepQueue.queue.length;
        for(i in 0...len){
            DepQueue.queue[i].get();
        }
        DepQueue.queue.splice(0, len);
        DepQueue.stage = IDLE;
        processDefQueue();
    }

    // Set a value to t
    public function set(t:T):Void {
        def({func:function(){ return t; }, deps:null});
    }

    function defFunc(func:Void->T, deps:Array<DVar<Dynamic>> = null):Void {
        DepQueue.stage = MARK;
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
            DepQueue.queue.push(this);
            propogate();
        }
    }

    public function def(data:{func:Void->T, deps:Array<DVar<Dynamic>>}):Void {
        queueDef(this, data);
    }

    public function get():T {
        if(!dirty) return val;

        if(!marked){
            marked = true;
        } else if(!cycle){
            DepQueue.cycleVars.push(this);
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
        if(force) DepQueue.queue.push(this);
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

    public function getHasFunc():Bool { return func != null; }
    public function getIsDirty():Bool { return dirty; }

    public function register(func:{old:T, change:T}->Void):Void {
        if(observers == null){
            observers = [func];
        } else {
            observers.push(func);
        }
    }

    function updateObservers(data:{old:T, change:T}):Void {
        for(observer in observers){
            observer(data);
        }
    }

    function processDefQueue():Void {
        if(DepQueue.defQueue.length == 0) {
            DepQueue.nCount = 0;
            return;
        }

        DepQueue.nCount++;
        if(DepQueue.nCount > DepQueue.nCap){
            DepQueue.defQueue.splice(0, DepQueue.defQueue.length);
            DepQueue.nCount = 0;
            throw "defQueue executed over max setting "+DepQueue.nCap;
        }

        var nextDef = DepQueue.defQueue.shift();
        var dvar = nextDef.dvar;
        var data = nextDef.data;
        dvar.defFunc(data.func, data.deps);
    }

    public function getStage():DepStage {
        return DepQueue.stage;
    }

    // If you want to change definitions within a register callback,
    // to ensure atomicity, you have to queue the definition
    // which will be executed as soon as DepStage is IDLE
    function queueDef(dvar:DVar<Dynamic>,
                      data: {
                             func:Void->Dynamic,
                             ?deps:Array<DVar<Dynamic>>
                           }){
        DepQueue.defQueue.push({dvar:dvar, data:data});
        if(DepQueue.stage == IDLE){
            processDefQueue();
        }
    }
}
