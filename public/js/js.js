
var js = (function () {

    function JSLib () {

    };

    JSLib.prototype.extend = function(Child, Parent) {
        var F = function() { }
        F.prototype = Parent.prototype
        Child.prototype = new F()
        Child.prototype.constructor = Child
        Child.superclass = Parent.prototype
    }

    return new JSLib();
}());




