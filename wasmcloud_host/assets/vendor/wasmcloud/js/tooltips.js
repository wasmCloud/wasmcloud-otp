import { Tooltip } from "../../@coreui/coreui-pro/js/coreui.bundle.min";

// TooltipCreate is a global function that can be called from the Phoenix context
// to create a CoreUI Toolip object.
window.TooltipCreate = function (element) {
  new Tooltip(element, {
    offset: function offset(_ref) {
      var placement = _ref.placement,
        reference = _ref.reference,
        popper = _ref.popper;

      if (placement === "bottom") {
        return [0, popper.height / 2];
      } else {
        return [];
      }
    },
  });
  element.dataset.toggle = "tooltip-created"
}