import { Popover } from '@coreui/coreui'
document.querySelectorAll('[data-toggle="popover"]').forEach(function (element) {
  // eslint-disable-next-line no-new
  new Popover(element);
});