package dvar;

import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.macro.Context;
using haxe.macro.Tools;
using Lambda;

typedef Path = Array<String>;

class DVarMacro {
    static var findType = "dvar.DVar";

    // We take in a function and return a set of the function and 
    // the list of variables it uses that are of type dep.DVar
    public static macro function dep(expr:Expr):Expr {

        var pos = Context.currentPos();
        var paths = [];
        var decls = new Map<String, Bool>();

        switch(expr.expr){
            case EFunction(_, fnc): findVars(expr, paths, [], decls);
            default: throw "Expected a function";
        }

        var iMap = new Map<String, String>();
        var is = [];
        for(path in paths){
            var start = path.shift();
            if(decls.exists(start) || start == "trace"){
                continue;
            }

            var ident;
            var identStr:String = null;
            var done:Bool = false;
            while(true){
                if(identStr == null){
                    ident = macro $i{start};
                    identStr = start;
                    if(path.length == 0){
                        done = true;
                    }
                } else {
                    var field = path.shift();
                    identStr += "."+field;
                    ident = macro $ident.$field;
                    if(path.length == 0) {
                        done = true;
                    }
                }

                if(ident == null) {
                    break;
                }

                var typ = Context.typeof(ident);
                switch(typ.follow()){
                    case TInst(ref,_):
                        var classType = ref.toString();
                        if(classType == findType){
                            // We already have this identifier in our set
                            if(iMap.exists(identStr)) break;
                            iMap.set(identStr,identStr);
                            is.push(ident);
                            break;
                        }
                    case TFun(args, ret): break;
                    default:
                }

                if(done){
                    break;
                }
            }
        }

        var ids = macro $a{is};
        if(is.length == 0){
            ids = macro $v{null};
        }

        var names = macro $v{iMap.array()};
        var objList:Array<{field:String, expr:Expr}> = [];
        objList.push({field:"func", expr:expr});
        objList.push({field:"deps", expr:ids});

        var result = {expr:EObjectDecl(objList), pos:pos};

        return macro $b{[result]};
    }

    static function findVars(e:Expr, arr:Array<Path>, path:Path, decls:Map<String, Bool>) {
        switch(e.expr) {
            case EConst(CIdent(s)):
                var path = path.copy();
                path.push(s);
                path.reverse();
                arr.push(path);
            case EField(e, field):
                var path = path.copy();
                path.push(field);
                findVars(e, arr, path, decls);
            case EVars(vars):
                for(evar in vars){
                    decls.set(evar.name, true);
                }
                ExprTools.iter(e, findVars.bind(_,arr,path,decls));
            case _:
                ExprTools.iter(e, findVars.bind(_,arr,path,decls));
        }
    }
}
