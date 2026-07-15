# Base image resolved by Foundry (anchored GAR ref or upstream pass-through)
ARG RBF_IMAGE_1
FROM ${RBF_IMAGE_1}

# Set working directory
WORKDIR /app

# Create a non-root user for security
RUN adduser -D appuser

# Switch to non-root user
USER appuser

# Set the entrypoint to show it's running
CMD ["echo", "BusyBox container is running!"]

# You can build this with:
# docker build -t my-busybox .
# 
# And run with:
# docker run my-busybox

