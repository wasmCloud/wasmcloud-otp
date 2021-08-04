import { Tooltip } from "../../@coreui/coreui-pro/js/coreui.bundle.min";
document
  .querySelectorAll('[data-toggle="tooltip"]')
  .forEach(function (element) {
    // eslint-disable-next-line no-new
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
  });
