

angular.module('citybusDisplay', [])
  .controller('CityBusStopController', function($scope, $interval, $window, $sce) {
    var vm = this;

    vm.routeID =  $sce.trustAsHtml("00");
    vm.direction = $sce.trustAsHtml("Not in Service");

    vm.nextStop = "Not in Service";
    vm.stopsList = [];

    $interval(() => {
      var date = new Date(),
          hours = date.getHours(),
          minutes = date.getMinutes() < 10 ? ('0' + date.getMinutes()) : date.getMinutes(), // prepending 0 if current minute is less than 10
          seconds = date.getSeconds();

      vm.time = `${hours}:${minutes}`;
    }, 1000)

    // overwriting plain javascript function so we can access from within the controller
    $window.updateDisplay = (data) => {
      console.warn(data);
      $scope.$evalAsync(function() {
        if (data.routeID)
          vm.routeID = $sce.trustAsHtml(parseTxt(data.routeID));

        if (data.direction)
          vm.direction = $sce.trustAsHtml(parseTxt(data.direction));

        if (data.routeColor)
          vm.routeColor = data.routeColor;


        if (data.tasklist && data.tasklist.length > 0) {
          // just getting name of stop since lua is sending an object
          vm.stopsList = data.tasklist.map((stopName) => stopName[1]);
          // we only want to show next 3
          vm.stopsList = vm.stopsList.length > 4 ? vm.stopsList.slice(0, 5) : vm.stopsList;
        }
        // if data.tasklist doesnt exist we presume that the stop list just needs to be updated.
        else
          vm.stopsList = data.length > 4 ? data.slice(0, 5) : data;

        if (vm.stopsList.length > 0) {
          // reversing order of stops so next stop shows up correctly
          vm.stopsList.reverse();
          vm.nextStop = vm.stopsList.splice(vm.stopsList.length-1, 1)[0];
        }
        else {
          vm.nextStop = "End of Line";
        }

      })
    }

    // TODO: Icon parsing
    function parseTxt(txt){
      var ptxt = txt.toString();
      ptxt = ptxt.replace(/(\[BNG\])/gi, `<svg style="width: 30px" viewBox="0 0 10 10"><use fill="white" width="100%" xlink:href="/ui/assets/sprites/svg-symbols.svg#general_beamng_logo_bw"></use></svg>`);
      ptxt = ptxt.replace(/(\[BUS\])/gi, `<svg style="width: 30px" viewBox="0 0 10 10"><use fill="white" width="100%" xlink:href="/ui/assets/sprites/svg-symbols.svg#material_directions_bus"></use></svg>`);
      ptxt = ptxt.replace(/(\[AIR\])/gi, `<svg style="width: 30px" viewBox="0 0 10 10"><use fill="white" width="100%" xlink:href="/ui/assets/sprites/svg-symbols.svg#material_local_airport"></use></svg>`);
      ptxt = ptxt.replace(/(\[ROTR\])/gi, `<svg style="width: 30px" viewBox="0 0 10 10"><use fill="white" width="100%" xlink:href="/ui/assets/sprites/svg-symbols.svg#material_rotate_right"></use></svg>`);
      ptxt = ptxt.replace(/(\[ROTL\])/gi, `<svg style="width: 30px" viewBox="0 0 10 10"><use fill="white" width="100%" xlink:href="/ui/assets/sprites/svg-symbols.svg#material_rotate_left"></use></svg>`);

      return ptxt;
    }

  });