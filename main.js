document.querySelector('.copy-btn').addEventListener('click', function() {
    const targetId = this.getAttribute('data-target');
    const codeElement = document.getElementById(targetId);
    const textToCopy = codeElement.textContent;

    navigator.clipboard.writeText(textToCopy).then(() => {
        showNotification('✅ Comando copiado al portapapeles');
        
        // Cambiar texto del botón temporalmente
        const originalText = this.textContent;
        this.textContent = '✓ Copiado!';
        this.style.background = '#059669';
        
        setTimeout(() => {
            this.textContent = originalText;
            this.style.background = '';
        }, 2000);
    }).catch(err => {
        showNotification('❌ Error al copiar', 'error');
        console.error('Error:', err);
    });
});

// Función para mostrar notificaciones
function showNotification(message, type = 'success') {
    const notification = document.getElementById('notification');
    notification.textContent = message;
    notification.style.background = type === 'error' ? '#ef4444' : '#10b981';
    notification.classList.add('show');
    
    setTimeout(() => {
        notification.classList.remove('show');
    }, 3000);
}