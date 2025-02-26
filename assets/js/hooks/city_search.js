// City Search Hook
const CitySearch = {
  mounted() {
    // Add event listener for handling the dropdown visibility when clicking outside
    document.addEventListener('click', (event) => {
      if (!this.el.contains(event.target)) {
        const customEvent = new CustomEvent('phx-blur');
        this.pushEventTo(this.el, 'search', { value: this.el.querySelector('input').value });
      }
    });

    // Add keydown event listener for keyboard navigation
    this.el.querySelector('input').addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        // Hide dropdown when ESC is pressed
        this.pushEventTo(this.el, 'search', { value: '' });
      }
    });
  }
};

export default CitySearch; 