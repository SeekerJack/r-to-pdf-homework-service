#P192  7.2

#（1）Descriptive statistics
x <- c(12, 15, 18, 20, 21, 24, 28)
mean(x)
sd(x)

#（2）Simple plot
plot(x, type = "b", main = "Sample values", xlab = "Index", ylab = "Value")

#P193  7.6

y <- c(11, 14, 16, 19, 23, 25, 27)
cor(x, y)
fit <- lm(y ~ x)
summary(fit)

#P254  10.1

group_a <- c(72, 75, 78, 81, 83)
group_b <- c(70, 73, 77, 80, 82)
t.test(group_a, group_b, paired = TRUE)
